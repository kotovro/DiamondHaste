#!/usr/bin/env python3
"""UDP relay that adds network latency between a game client and the host.

For manual checks "under 150 ms" in two windows on one PC (qa-manual, H3).
The client connects to the relay port instead of the host port; every packet
is held for --delay ms in each direction, so the round trip is 2 x delay
(default 75 ms each way = 150 ms ping). Optional --jitter and --loss.

    python tools/lag_proxy.py                     # 127.0.0.1:24681 -> 127.0.0.1:24680, 75 ms each way
    python tools/lag_proxy.py --delay 100 --jitter 10 --loss 1
    python tools/lag_proxy.py --self-test         # checks itself with a local echo, no game needed

Only the Python standard library is used. Works for ENet (Godot's default transport).
"""
from __future__ import annotations

import argparse
import heapq
import itertools
import random
import selectors
import socket
import sys
import threading
import time

DEFAULT_HOST_PORT = 24680   # Network.DEFAULT_PORT in scripts/net/network.gd
DEFAULT_LISTEN_PORT = 24681
MAX_DATAGRAM = 65535


class LagProxy:
    """Relays datagrams client <-> target with a delay. One upstream socket per client address."""

    def __init__(self, listen: tuple[str, int], target: tuple[str, int],
                 delay_ms: float, jitter_ms: float = 0.0, loss_percent: float = 0.0,
                 seed: int | None = None) -> None:
        self.target = target
        self.delay = delay_ms / 1000.0
        self.jitter = jitter_ms / 1000.0
        self.loss = loss_percent / 100.0
        self.random = random.Random(seed)
        self.selector = selectors.DefaultSelector()
        self.front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.front.bind(listen)
        self.front.setblocking(False)
        self.selector.register(self.front, selectors.EVENT_READ, None)
        self.upstream: dict[tuple[str, int], socket.socket] = {}
        self.queue: list[tuple[float, int, socket.socket, bytes, tuple[str, int]]] = []
        self.order = itertools.count()  # keeps FIFO order for equal due times
        self.running = True
        self.relayed = 0
        self.dropped = 0

    @property
    def listen_address(self) -> tuple[str, int]:
        return self.front.getsockname()

    def _schedule(self, sock: socket.socket, data: bytes, to: tuple[str, int]) -> None:
        if self.loss > 0.0 and self.random.random() < self.loss:
            self.dropped += 1
            return
        delay = self.delay
        if self.jitter > 0.0:
            delay = max(0.0, delay + self.random.uniform(-self.jitter, self.jitter))
        heapq.heappush(self.queue, (time.monotonic() + delay, next(self.order), sock, data, to))

    def _upstream_for(self, client: tuple[str, int]) -> socket.socket:
        sock = self.upstream.get(client)
        if sock is None:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind(("127.0.0.1" if self.target[0] in ("127.0.0.1", "localhost") else "0.0.0.0", 0))
            sock.setblocking(False)
            self.selector.register(sock, selectors.EVENT_READ, client)
            self.upstream[client] = sock
            print(f"client {client[0]}:{client[1]} connected via port {sock.getsockname()[1]}", flush=True)
        return sock

    def _flush_due(self) -> None:
        now = time.monotonic()
        while self.queue and self.queue[0][0] <= now:
            _, _, sock, data, to = heapq.heappop(self.queue)
            try:
                sock.sendto(data, to)
                self.relayed += 1
            except OSError:
                self.dropped += 1

    def serve(self) -> None:
        while self.running:
            timeout = 0.05
            if self.queue:
                timeout = max(0.0, min(timeout, self.queue[0][0] - time.monotonic()))
            for key, _ in self.selector.select(timeout):
                sock: socket.socket = key.fileobj  # type: ignore[assignment]
                try:
                    data, sender = sock.recvfrom(MAX_DATAGRAM)
                except (BlockingIOError, ConnectionResetError, OSError):
                    continue  # Windows reports ICMP "port unreachable" as a recv error
                if sock is self.front:
                    self._schedule(self._upstream_for(sender), data, self.target)
                else:
                    client: tuple[str, int] = key.data
                    self._schedule(self.front, data, client)
            self._flush_due()

    def close(self) -> None:
        self.running = False
        for sock in [self.front, *self.upstream.values()]:
            try:
                self.selector.unregister(sock)
            except (KeyError, ValueError):
                pass
            sock.close()


def self_test(delay_ms: float) -> int:
    """Echo server behind the proxy: round trip must be about 2 x delay."""
    echo = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    echo.bind(("127.0.0.1", 0))
    stop = threading.Event()

    def run_echo() -> None:
        echo.settimeout(0.1)
        while not stop.is_set():
            try:
                data, addr = echo.recvfrom(MAX_DATAGRAM)
                echo.sendto(data, addr)
            except (socket.timeout, OSError):
                continue

    proxy = LagProxy(("127.0.0.1", 0), echo.getsockname(), delay_ms)
    threads = [threading.Thread(target=run_echo, daemon=True), threading.Thread(target=proxy.serve, daemon=True)]
    for t in threads:
        t.start()
    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client.settimeout(2.0)
    rtts = []
    ok = True
    try:
        for i in range(10):
            payload = f"ping {i}".encode()
            start = time.monotonic()
            client.sendto(payload, proxy.listen_address)
            data, _ = client.recvfrom(MAX_DATAGRAM)
            rtts.append((time.monotonic() - start) * 1000.0)
            if data != payload:
                print(f"FAIL: payload mismatch {data!r} != {payload!r}")
                ok = False
    except socket.timeout:
        print("FAIL: no reply through the proxy")
        ok = False
    finally:
        stop.set()
        proxy.close()
        client.close()
        echo.close()
    if rtts:
        expected = 2 * delay_ms
        low, high = min(rtts), max(rtts)
        print(f"round trip: min {low:.1f} ms, max {high:.1f} ms, expected ~{expected:.0f} ms")
        if low < expected * 0.95 or high > expected + 60:
            print("FAIL: round trip out of range")
            ok = False
    print("SELF-TEST OK" if ok else "SELF-TEST FAILED")
    return 0 if ok else 1


def parse_address(text: str, default_port: int) -> tuple[str, int]:
    host, _, port = text.rpartition(":")
    if not host:
        return text, default_port
    return host, int(port)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--listen-port", type=int, default=DEFAULT_LISTEN_PORT, help="port the client connects to")
    parser.add_argument("--target", default=f"127.0.0.1:{DEFAULT_HOST_PORT}", help="host address:port")
    parser.add_argument("--delay", type=float, default=75.0, help="one-way delay, ms (round trip = 2x)")
    parser.add_argument("--jitter", type=float, default=0.0, help="random +/- delay, ms")
    parser.add_argument("--loss", type=float, default=0.0, help="packet loss, percent")
    parser.add_argument("--self-test", action="store_true", help="check the proxy with a local echo and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test(args.delay)

    proxy = LagProxy(("127.0.0.1", args.listen_port), parse_address(args.target, DEFAULT_HOST_PORT),
                     args.delay, args.jitter, args.loss)
    print(f"lag proxy: 127.0.0.1:{args.listen_port} -> {args.target}, "
          f"{args.delay:g} ms each way (ping ~{2 * args.delay:g} ms), "
          f"jitter {args.jitter:g} ms, loss {args.loss:g}%. Ctrl+C to stop.", flush=True)
    try:
        proxy.serve()
    except KeyboardInterrupt:
        pass
    finally:
        proxy.close()
        print(f"stopped: relayed {proxy.relayed}, dropped {proxy.dropped}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
