package iptables

import (
	"fmt"
	"os/exec"
	"strconv"
)

const bypassMark = "0x1"

// SetupRedirect installs OUTPUT nat redirect for DNS (udp/tcp 53 -> port).
// Packets carrying mark bypassMark will RETURN (used by the proxy's own upstream
// queries to avoid redirect loops). Requires CAP_NET_ADMIN inside the namespace.
func SetupRedirect(port int) error {
	targetPort := strconv.Itoa(port)

	rules := [][]string{
		// Bypass packets marked by the proxy itself (see dnsproxy dialer).
		{"iptables", "-t", "nat", "-A", "OUTPUT", "-p", "udp", "--dport", "53", "-m", "mark", "--mark", bypassMark, "-j", "RETURN"},
		{"iptables", "-t", "nat", "-A", "OUTPUT", "-p", "tcp", "--dport", "53", "-m", "mark", "--mark", bypassMark, "-j", "RETURN"},
		// Redirect all other DNS traffic to local proxy port.
		{"iptables", "-t", "nat", "-A", "OUTPUT", "-p", "udp", "--dport", "53", "-j", "REDIRECT", "--to-port", targetPort},
		{"iptables", "-t", "nat", "-A", "OUTPUT", "-p", "tcp", "--dport", "53", "-j", "REDIRECT", "--to-port", targetPort},
	}

	for _, args := range rules {
		if output, err := exec.Command(args[0], args[1:]...).CombinedOutput(); err != nil {
			return fmt.Errorf("iptables command failed: %v (output: %s)", err, output)
		}
	}
	return nil
}
