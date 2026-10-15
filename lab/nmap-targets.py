#!/usr/bin/env python3
"""Loopback-only TCP listeners for capturing real nmap output.

Binds a handful of ports on 127.0.0.1 with trivial banners so `nmap -sV`
has something real to fingerprint. No service logic beyond the banner.

    ./lab/nmap-targets.py        then     nmap -sV -p 2200,2280,2225,2253 127.0.0.1
"""
import socket
import threading

BANNERS = {
    2200: b"SSH-2.0-OpenSSH_9.6p1 Debian-3\r\n",
    2280: b"HTTP/1.1 200 OK\r\nServer: lab-httpd/1.0\r\n\r\n",
    2225: b"220 lab-smtp ESMTP Postfix\r\n",
    2253: b"",  # closed-ish: accepts then hangs up, no banner
}


def serve(port, banner):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port))
    s.listen(5)
    while True:
        conn, _ = s.accept()
        try:
            if banner:
                conn.sendall(banner)
        except Exception:
            pass
        finally:
            conn.close()


if __name__ == "__main__":
    for port, banner in BANNERS.items():
        threading.Thread(target=serve, args=(port, banner), daemon=True).start()
    print(f"listening on 127.0.0.1: {sorted(BANNERS)}")
    threading.Event().wait()
