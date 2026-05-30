cask "mwitch" do
  version "0.2.1"
  sha256 :no_check

  url "https://github.com/viraatdas/mwitch/releases/download/v#{version}/mwitch.zip",
      verified: "github.com/viraatdas/mwitch/"
  name "mwitch"
  desc "Native window switcher for Cmd+Tab"
  homepage "https://mwitch.viraat.dev/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "mwitch.app"

  zap trash: [
    "~/Library/Caches/dev.mwitch.app",
    "~/Library/HTTPStorages/dev.mwitch.app",
    "~/Library/Logs/mwitch.log",
    "~/Library/Preferences/dev.mwitch.app.plist",
  ]
end
