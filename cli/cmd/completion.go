package cmd

import (
	"os"

	"github.com/spf13/cobra"
)

var completionCmd = &cobra.Command{
	Use:   "completion [bash|zsh|fish]",
	Short: "Generate shell completion scripts",
	Long: `Generate shell completion scripts for sb.

To load completions:

Bash:
  $ source <(sb completion bash)
  # Or add to ~/.bashrc:
  $ sb completion bash >> ~/.bashrc

Zsh:
  $ source <(sb completion zsh)
  # Or install system-wide:
  $ sb completion zsh > "${fpath[1]}/_sb"

Fish:
  $ sb completion fish | source
  # Or install system-wide:
  $ sb completion fish > ~/.config/fish/completions/sb.fish
`,
	DisableFlagsInUseLine: true,
	ValidArgs:             []string{"bash", "zsh", "fish"},
	Args:                  cobra.MatchAll(cobra.ExactArgs(1), cobra.OnlyValidArgs),
	RunE: func(cmd *cobra.Command, args []string) error {
		switch args[0] {
		case "bash":
			return rootCmd.GenBashCompletionV2(os.Stdout, true)
		case "zsh":
			return rootCmd.GenZshCompletion(os.Stdout)
		case "fish":
			return rootCmd.GenFishCompletion(os.Stdout, true)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(completionCmd)
}
