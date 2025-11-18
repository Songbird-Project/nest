package subcommands

import (
	"os/exec"

	"github.com/Jguer/go-alpm/v2"
)

var installArgs = []string{"-S", "-r $NEST_GEN_ROOT", "-b $NEST_GEN_ROOT/db", "--noprogressbar"}

type InstallCmd struct {
	Local     string `arg:"-l,--local" help:"install using a local build file or package archive"`
	RemoteURL string `arg:"-r,--remote" help:"install using a remote build file or package archive"`

	PkgNames []string `arg:"positional" help:"names of packages to install"`
}

func InstallPkg(handle *alpm.Handle, args *InstallCmd) error {
	pkgs := args.PkgNames

	pacmanArgs := append(installArgs, pkgs...)
	searchMainRepos := exec.Command("pacman", pacmanArgs...)
	_, err := searchMainRepos.Output()
	if err != nil {
		return err
	}
	return nil
}
