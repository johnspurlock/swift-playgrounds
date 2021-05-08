import SwiftUI
import PlaygroundSupport
import AVKit

// Demonstrates the difficulty of setting a custom User-Agent when using Apple's AVPlayer

// These examples all start playing an mp3 at a given url without pre-downloading
// Similar to Apple Podcast's behavior when hitting the play icon on /undownloaded/ episodes

// This url supports HTTP Range requests
let audioUrl = "https://api.livewire.io/reflections/68b6d33a70c0473aac6b00573449b2a9.mp3?noip"

// This url does not support HTTP Range requests
let audioUrlNotSupportingRangeRequests = "https://api.livewire.io/reflections/68b6d33a70c0473aac6b00573449b2a9.mp3?noip&norange"

// Custom User-Agent we would like to send (for server-side attribution purposes)
let myUserAgent = "MyPodcastApp/1.5 iOS https://mypodcastapp.example.com/"

// standard player used in all examples
let player = AVPlayer()

let customLoaderDelegate = CustomLoaderDelegate(userAgent: myUserAgent)


struct ContentView: View {
    var body: some View {
        
        VStack {
        
            // Example 1: Basic AVKit playback, no user-agent specified
            // Apple's CFNetwork will be used under the hood to make the underlying HTTP calls using its own User-Agent header
            Button("AVPlayer · default User-Agent ❌") {
                player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: audioUrl)!))
                player.play() // "Apple Core Media"
            }.padding()
       
            // Example 2: Same AVKit player, but customized using an asset with "AVURLAssetHTTPHeaderFieldsKey" and a custom User-Agent
            // Apple's CFNetwork will be used under the hood to make the underlying HTTP calls using the custom User-Agent header
            // However, "AVURLAssetHTTPHeaderFieldsKey" appears nowhere in Apple's public documentation, and can break at any time,
            // also possibly grounds for an app rejection!
            Button("AVPlayer · custom User-Agent · undocumented API · range ✅") {
                let headers: [String : String] = ["User-Agent": myUserAgent]
                let asset = AVURLAsset(url: URL(string: audioUrl)!, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                player.play() // "My Podcast App"
            }.padding()
            
            // Example 2b: Same as example 2, but the media server does not support range requests
            // Apple's CFNetwork will be used under the hood to make the first HTTP call using the custom User-Agent header
            // (the first call is for the first two bytes) - however, the custom header is not used for the subsequent call
            // (ie, the call for the entire file without a range, the one that gets played!)
            Button("AVPlayer · custom User-Agent · undocumented API · no range ❌") {
                let headers: [String : String] = ["User-Agent": myUserAgent]
                let asset = AVURLAsset(url: URL(string: audioUrlNotSupportingRangeRequests)!, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                player.play() // "Apple Core Media"
            }.padding()
            
            // Example 3: Same AVKit player, but customized using a resource loader delegate, a documented public API (AVAssetResourceLoaderDelegate)
            // The custom delegate is responsible for providing data back to the player, so it can make the HTTP calls itself,
            // which means it can easily set the User-Agent (using the standard URLRequest is this demo)
            // This is much more difficult integration, since the player calls the delegate multiple times with different ranges etc
            Button("AVPlayer · custom User-Agent · documented API · range ✅") {
                // must not use "https" or "http", the custom loader delegate will not be called!
                let asset = AVURLAsset(url: URL(string: "custom-\(audioUrl)")!)
                asset.resourceLoader.setDelegate(customLoaderDelegate, queue: .global(qos: .default))
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                player.play() // "My Podcast App"
            }.padding()
            
            // Example 3b: Same as example 3, but the media server does not support range requests
            // This still works since we are in complete control of the underlying HTTP calls
            Button("AVPlayer · custom User-Agent · documented API · no range ✅") {
                // must not use "https" or "http", the custom loader delegate will not be called!
                let asset = AVURLAsset(url: URL(string: "custom-\(audioUrlNotSupportingRangeRequests)")!)
                asset.resourceLoader.setDelegate(customLoaderDelegate, queue: .global(qos: .default))
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                player.play() // "My Podcast App"
            }.padding()
        }
        
    }
    
}

// MARK: - Additional code to support Example 3 (custom AVAssetResourceLoaderDelegate)


// Helper class to handle loading of a custom asset url.
// This shows how the underlying http calls can be completely customized by the app at this point.
// The code below should not be copy and pasted as is!  It's deliberately minimal to prove out the mechanism.
// A real app should not pre-download and cache the entire file, otherwise there is no benefit to streaming.
// It should turn around and make HTTP range requests, gracefully handle failures, etc.
// It's done below to keep things short, and to show the complexity of this approach (a minimal example is already complicated!)
class CustomLoaderDelegate : NSObject, AVAssetResourceLoaderDelegate {
    let userAgent: String
    var fetchedUrlData = [URL: Data]() // cache the response per url, since we get multiple callbacks for the same resource
    
    init(userAgent: String) {
        self.userAgent = userAgent
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        // handle requests from the player, turn around and make an HTTP call ourself if we have not already fetched it
        // then send the data back to the player
        if let url = loadingRequest.request.url, let dataRequest = loadingRequest.dataRequest {
            func finishRequestWithData(_ data: Data) {
                if let contentInformationRequest = loadingRequest.contentInformationRequest {
                    contentInformationRequest.isByteRangeAccessSupported = false
                    contentInformationRequest.contentType = "audio/mpeg"
                    contentInformationRequest.contentLength = Int64(data.count)
                }
                if (dataRequest.requestsAllDataToEndOfResource) {
                    dataRequest.respond(with: data)
                    loadingRequest.finishLoading()
                } else {
                    let start = Int(dataRequest.requestedOffset)
                    let end = Int(dataRequest.requestedOffset) + dataRequest.requestedLength
                    dataRequest.respond(with: data[start..<end])
                    loadingRequest.finishLoading()
                }
            }
            if let data = self.fetchedUrlData[url] {
                finishRequestWithData(data)
            } else {
                // fetch the resource with our custom user-agent using URLRequest
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.scheme = "https"
                fetch(url: components.url!, userAgent: self.userAgent) { data in
                    self.fetchedUrlData[url] = data
                    finishRequestWithData(data)
                }
            }
        }
        
        return true // we can handle it
    }
}

// Helper function to fetch an url
// This is deliberately simplistic, a real app should make multiple range requests, implement their own cache, etc.
func fetch(url: URL, userAgent: String, onData: @escaping (Data) -> ()) {
    print("fetch \(url)")
    let session = URLSession.shared
    
    var urlRequest = URLRequest(url: url)
    urlRequest.addValue(userAgent, forHTTPHeaderField: "User-Agent") // finally, setting the custom User-Agent!
    
    let task = session.dataTask(with: urlRequest) { (data, response, error) in
        guard error == nil else {
            print(error!)
            return
        }
        guard let responseData = data else {
            print("Fetch error: no response data")
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Fetch error: not an HTTP response")
            return
        }
        guard httpResponse.statusCode == 200 else {
            print("Fetch error: not an HTTP 200")
            return
        }
        onData(responseData)
    }
    task.resume()
}

// run the playground
PlaygroundPage.current.setLiveView(ContentView())
