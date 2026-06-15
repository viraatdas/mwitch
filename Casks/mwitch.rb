cask "mwitch" do
  version "0.3.5"
  sha256 "a5e76b970d19e96f5f67d087ac3d5ab5b501c9eef03b731308f69a3f5939ed74"

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
