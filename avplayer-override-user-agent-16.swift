import SwiftUI
import PlaygroundSupport
import AVKit

// Demonstrates setting a custom User-Agent when using Apple's AVPlayer

// These examples all start playing an mp3 at a given url without pre-downloading
// Similar to Apple Podcast's behavior when hitting the play icon on _undownloaded_ episodes

// You can run this yourself in the new Xcode 14 beta, and copying and pasting this into a new playground

// (Running it in the Swift Playgrounds app will fail, as that app has not been updated with the new sdks yet)

// Video of the demo running: https://twitter.com/johnspurlock/status/1533969528039821312

// MARK: - Demo setup

// This url supports HTTP Range requests
let audioUrl = "https://api.livewire.io/reflections/68b6d33a70c0473aac6b00573449b2a9.mp3?noip"

// This url does not support HTTP Range requests
let audioUrlNotSupportingRangeRequests = "https://api.livewire.io/reflections/68b6d33a70c0473aac6b00573449b2a9.mp3?noip&norange"

// Custom User-Agent we would like to send (for server-side attribution purposes)
let myUserAgent = "MyPodcastApp/1.5 iOS https://mypodcastapp.example.com/"

// standard player used in all examples
let player = AVPlayer()

// UI for the demo
struct ContentView: View {
    var body: some View {
        
        VStack {
        
            // Example 1: Basic AVKit playback, no user-agent specified
            // Apple's CFNetwork will be used under the hood to make the underlying HTTP calls using its own User-Agent header
            Button("AVPlayer · default User-Agent ❌") {
                player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: audioUrl)!))
                player.play() // "Apple Core Media"
            }.padding()
            
            // Example 2: Same AVKit player, but customized using an asset with AVURLAssetHTTPUserAgentKey and a custom User-Agent
            // Apple's CFNetwork will be used under the hood to make the underlying HTTP calls using the custom User-Agent header
            // AVURLAssetHTTPUserAgentKey is a documented, new public API as of iOS 16
            // https://developer.apple.com/documentation/avfoundation/avurlassethttpuseragentkey
            Button("AVPlayer · custom User-Agent iOS 16 · server supports range ✅") {
                let asset = AVURLAsset(url: URL(string: audioUrl)!, options: [AVURLAssetHTTPUserAgentKey: myUserAgent])
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                player.play() // "My Podcast App"
            }.padding()
            
            // Example 2b: Same as example 2, but the media server does not support range requests
            // Apple's CFNetwork will be used under the hood to make the first HTTP call using the custom User-Agent header
            // (the first call is for the first two bytes) - however, the custom header is not used for the subsequent call
            // (ie, the call for the entire file without a range, the one that gets played!)
            Button("AVPlayer · custom User-Agent iOS 16 · server does not support range  ❌") {
                let asset = AVURLAsset(url: URL(string: audioUrlNotSupportingRangeRequests)!, options: [AVURLAssetHTTPUserAgentKey: myUserAgent])
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                player.play() // "Apple Core Media"
            }.padding()
       
        }
        
    }
    
}

// run the playground
PlaygroundPage.current.setLiveView(ContentView())

// MARK: - More information

/*

 Here are the http requests that AVPlayer makes when playing an URL asset (and setting AVURLAssetHTTPUserAgentKey):
 
 First:
  - requests the first two bytes to determine if the server supports range requests
  - never uses the response for playback

     GET https://mediahost.com/path/to/audio.mp3
     accept: *∕*
     accept-encoding: gzip
     accept-language: en-US,en;q=0.9
     connection: Keep-Alive
     priority: u=3, i
     range: bytes=0-1
     user-agent: MyPodcastApp/1.5 iOS https://mypodcastapp.example.com/
     x-playback-session-id: 7E3C5DC1-9EBD-4198-B5B7-DBE938AB01C6

 If the server supports range requests (ie the server returns 206 with the appropriate Content-Range, Content-Length, and body):
   - requests the media using one or more range requests
   - uses the response for playback
 
     GET https://mediahost.com/path/to/audio.mp3
     accept: *∕*
     accept-encoding: gzip
     accept-language: en-US,en;q=0.9
     connection: Keep-Alive
     range: bytes=0-36143
     user-agent: MyPodcastApp/1.5 iOS https://mypodcastapp.example.com/
     x-playback-session-id: 7E3C5DC1-9EBD-4198-B5B7-DBE938AB01C6
 
 If the server does not support range requests (ie it returns 200 with the full body for the intitial request or otherwise fails)
  - re-requests the media using a single non-range fallback request
  - uses the response for playback
 
     GET https://mediahost.com/path/to/audio.mp3
     accept: *∕*
     accept-encoding: gzip
     accept-language: en-US,en;q=0.9
     connection: Keep-Alive
     icy-metadata: 1
     priority: u=3, i
     user-agent: AppleCoreMedia/1.0.0.20A5283p (iPad; U; CPU OS 16_0 like Mac OS X; en_us)
     x-playback-session-id: 11FAC289-7DA2-4E6B-BEF2-8424BC420262
 
 Note that:
  - the custom user agent set via AVURLAssetHTTPUserAgentKey is only sent for range requests - if the server does not support it, the fallback request used for content playback still sends AppleCoreMedia!
  - if the AVURLAssetHTTPUserAgentKey is not set, it sends AppleCoreMedia for all requests
  - x-playback-session-id can be used to determine a single client play request
  - the fallback request includes a request for shoutcast metadata, presumably to avoid another request if the url happens to be a shoutcast stream
 
 */
