//go:build linux

package dnsproxy

import (
	"net"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

// dialerWithMark sets SO_MARK so iptables can RETURN marked packets (bypass
// redirect for proxy's own upstream DNS queries).
func (p *Proxy) dialerWithMark() *net.Dialer {
	return &net.Dialer{
		Timeout: 5 * time.Second,
		Control: func(network, address string, c syscall.RawConn) error {
			var opErr error
			if err := c.Control(func(fd uintptr) {
				opErr = unix.SetsockoptInt(int(fd), unix.SOL_SOCKET, unix.SO_MARK, 0x1)
			}); err != nil {
				return err
			}
			return opErr
		},
	}
}
