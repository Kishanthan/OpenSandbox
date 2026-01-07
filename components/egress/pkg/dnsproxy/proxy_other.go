//go:build !linux

package dnsproxy

import (
	"net"
	"time"
)

// Non-linux: no SO_MARK; return basic dialer.
func (p *Proxy) dialerWithMark() *net.Dialer {
	return &net.Dialer{Timeout: 5 * time.Second}
}
