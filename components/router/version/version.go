package version

import (
	"fmt"
	"runtime"
)

// Version package values is auto-generated, the following values will be overridden at build time.
var (
	// Version represents the version of taskline suite.
	Version = "1.0.0"

	// BuildTime is the time when taskline-operator binary is built
	BuildTime = "assigned-at-build-time"

	// GitCommit is the commit id to build taskline-operator
	GitCommit = "assigned-at-build-time"
)

// EchoVersion is used to echo current binary build info for diagnosing
func EchoVersion() {
	fmt.Println("=====================================================")
	fmt.Println(" OpenSandbox Router")
	fmt.Println("-----------------------------------------------------")
	fmt.Printf(" Version     : %s\n", Version)
	fmt.Printf(" Git Commit  : %s\n", GitCommit)
	fmt.Printf(" Build Time  : %s\n", BuildTime)
	fmt.Printf(" Go Version  : %s\n", runtime.Version())
	fmt.Printf(" Platform    : %s/%s\n", runtime.GOOS, runtime.GOARCH)
	fmt.Println("=====================================================")
}
