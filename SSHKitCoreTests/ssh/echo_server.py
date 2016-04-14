#!/usr/bin/env python

"""

An echo server (the echo protocol is standardized in RFC 862). This
one implements only TCP.

Implemented with Python standard module SocketServer.
# http://www.bortzmeyer.org/files/echoserver.py

"""

import SocketServer
from SocketServer import TCPServer, ThreadingMixIn, StreamRequestHandler
import optparse
import sys
import time
import re
import socket

def current_time():
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time()))


# We mix with ThreadingMixIn to allow several simultaneous
# clients. Otherwise, a slow client may block everyone.
class ThreadingTCPServer(ThreadingMixIn, TCPServer):
    def server_activate(self):
        SocketServer.TCPServer.server_activate(self)
        sys.stdout.write("Server listening on %s\n" % (self.server_address,) )
        sys.stdout.flush()

    def server_bind(self):
        # Override this method to be sure v6only is false: we want to
        # listen to both IPv4 and IPv6!
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, False)
        SocketServer.TCPServer.server_bind(self)


# StreamRequestHandler provides us with the rfile and wfile attributes
class EchoHandler(StreamRequestHandler):
    def log(self, peer, size):
        mapped = re.compile("^::ffff:", re.IGNORECASE)
        peer = re.sub(mapped, "", peer)  # Clean IPv4-mapped addresses because I find
        # them confusing.
        sys.stdout.write("%s - %s - %i bytes\n" % (current_time(),
                                                   peer, size))

    def handle(self):
        """ Echoes (sends back) whatever it reads """
        # Warning, the Python read() is not the same as the C
        # read(). It operates on file objects, not sockets and has
        # different semantics.
        #
        # Just using read() will block until the TCP connection is
        # closed. We do not know the size in advance, hence the loop
        # with a size of 1. Now, you understand why HTTP has
        # Content-Length and why EPP-over-TCP prepends the length of
        # the XML element...
        #
        # Another solution would be to use self.request (the socket)
        # and to call recv(1024) and send() on it. Tests show that it
        # is *much* slower (twenty times slower on a local Ethernet).
        #
        data = "DUMMY"
        size = 0
        peer = self.client_address[0]
        while data != "":
            data = self.rfile.read(1)
            try:
                self.wfile.write(data)
                size = size + len(data)
            except socket.error:  # Client went away, do not take that data into account
                data = ""
        self.log(peer, size)

if __name__ == '__main__':
    parser = optparse.OptionParser()
    parser.add_option('-p', '--port',
                      help="specify listening port",
                      type="int",
                      default="2200", # Standard port is 7 but, on Unix, you need to be root to use it
                      )
                      
    options, args = parser.parse_args()

    ThreadingTCPServer.allow_reuse_address = True
    # SocketServer should transparently accept IPv6 connections. But
    # it does not. So, we tell it. Note that using socket.AF_INET6
    # allows to receive *both* IPv4 and IPv6 (and, no, we cannot use
    # socket.AF_UNSPEC, it raises an exception :-( ), thanks to the
    # socket.IPV6_V6ONLY that we use in server_bind.
    #
    # See the very detailed study
    # <https://edms.cern.ch/document/971407>
    ThreadingTCPServer.address_family = socket.AF_INET6
    server = ThreadingTCPServer(("", options.port), EchoHandler)
    server.serve_forever()
