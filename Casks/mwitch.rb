cask "mwitch" do
  version "0.3.4"
  sha256 "c0573db6238807f3a44fc8b72dd435683d2ccb061c4dcb5bc310552a58802102"

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
