cask "mwitch" do
  version "1.0.1"
  sha256 "687e828d4d4c59d839968ddb0ab1865d6d1a1894638425e0d930656cf1240f1c"

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
