cask "better-cheatsheet" do
  version "1.1.0"
  sha256 "c84c8116bb3dc172da0035c7cbd17b7c9f1a443df5647839068d18d432a29c57"

  url "https://github.com/vhai2801/BetterCheatsheet/releases/download/v#{version}/BetterCheatsheet-#{version}.zip"
  name "Better Cheatsheet"
  desc "Menu-bar keyboard-shortcut notes app with a floating cheatsheet overlay"
  homepage "https://github.com/vhai2801/BetterCheatsheet"

  depends_on macos: :ventura

  app "BetterCheatsheet.app"

  # Not notarized (no paid Apple Developer ID) - without this, Gatekeeper
  # would block the first launch with an "unidentified developer" prompt.
  postflight do
    system_command "/usr/bin/xattr",
                    args: ["-dr", "com.apple.quarantine", "#{appdir}/BetterCheatsheet.app"],
                    sudo: false
  end

  zap trash: [
    "~/Library/Application Support/BetterCheatsheet",
    "~/Library/Preferences/com.blub.bettercheatsheet.plist",
  ]
end
