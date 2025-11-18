package core

import (
	"slices"

	"gopkg.in/ini.v1"
)

func GetConfig() (*NestConfig, error) {
	nonRepoSections := []string{"style"}
	cfg := &NestConfig{}

	cfgFile, err := ini.Load("/nest/config.conf")
	if err != nil {
		return nil, err
	}

	cfg.Color = cfgFile.Section("style").Key("Color").MustBool(true)

	cfgSections := cfgFile.SectionStrings()

	repos := []*Repo{}
	for _, section := range cfgSections {
		if !slices.Contains(nonRepoSections, section) {
			repo := &Repo{
				Server:   cfgFile.Section(section).Key("Server").String(),
				SigLevel: cfgFile.Section(section).Key("SigLevel").String(),
				Include:  cfgFile.Section(section).Key("Include").String(),
			}

			repos = append(repos, repo)
		}
	}

	return cfg, nil
}

func MakePacmanConfig() error {
	return nil
}
