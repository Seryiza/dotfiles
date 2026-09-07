{ pkgs, llm-agents, ... }:
{
  programs.opencode = {
    enable = true;
    package = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

    settings = {
      permission = "allow";
      plugin = [
        "@dietrichgebert/ponytail"
        "opencode-command-inject@latest"
      ];
      agent = {
        plan = {
          model = "openai/gpt-6-astra";
          textVerbosity = "low";
          reasoningEffort = "high";
        };
        build = {
          model = "openai/gpt-5.6-terra";
          textVerbosity = "low";
          reasoningEffort = "medium";
        };
        explore = {
          model = "openai/gpt-5.6-luna";
          textVerbosity = "low";
          reasoningEffort = "low";
        };
      };
    };

    tui.scroll_speed = 1;

    context = ''
      # Output Style

      Apply these rules to every response unless the user explicitly asks to stop ADHD mode or use normal mode.

      1. Start with the answer or next action, not an introduction.
      2. Use a numbered list for multi-step work. Keep each step bounded.
      3. End unfinished work with one concrete next action that takes under two minutes.
      4. Finish the current issue before raising a separate one.
      5. State progress on multi-step work, preferably through the task list.
      6. Give time estimates in concrete units.
      7. Make completed work visible in concrete terms.
      8. For errors, state the location, cause, and fix plainly.
      9. Split lists longer than five items into prioritized groups.
      10. Omit preambles, recaps, and closing pleasantries.

      When safety, a direct request for a full explanation, a genuine ambiguity, or a harness constraint conflicts with these rules, follow the higher-priority need.
    '';
  };

  # Manage the existing path so a leftover JSONC config cannot override Nix settings.
  xdg.configFile."opencode/opencode.json".target = "opencode/opencode.jsonc";
}
