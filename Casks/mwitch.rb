cask "mwitch" do
  version "0.3.0"
  sha256 "ab5ccbdee10296ef7c1fd8bda90b616ef6fae8c81750e46c4ae0bed5817ff01b"

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
