import SwiftUI
import PlaygroundSupport
import AVKit

let audioUrl = "https://api.livewire.io/reflections/68b6d33a70c0473aac6b00573449b2a9.mp3"
let player = AVPlayer()
let customLoaderDelegate = CustomLoaderDelegate(userAgent: "MyPodcastApp/1.5 iOS https://mypodcastapp.example.com/")

struct ContentView: View {
    var body: some View {
        HStack {
            // Example using the most basic invocation of playing audio, no user-agent specified
            Button("Default AV Player") {
                player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: audioUrl)!))
                player.play() // "AppleCoreMedia"
            }.padding()
       
            // Example using a custom resource loader, can set the user-agent
            Button("Custom AV Player") {
                // must not use "https" or "http", the custom loader delegate will not be called!
                let asset = AVURLAsset(url: URL(string: "custom-\(audioUrl)")!)
                asset.resourceLoader.setDelegate(customLoaderDelegate, queue: .global(qos: .default))
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                player.play() // "Apache-HttpClient"
            }.padding()
        }
    }
}

// helper class to handle loading of a custom asset url
class CustomLoaderDelegate : NSObject, AVAssetResourceLoaderDelegate {
    let userAgent: String
    var fetchedUrlData = [URL: Data]() // cache the response per url, since we get multiple callbacks for the same resource
    
    init(userAgent: String) {
        self.userAgent = userAgent
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
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

// helper to fetch an url with a custom user-agent
func fetch(url: URL, userAgent: String, onData: @escaping (Data) -> ()) {
    print("fetch \(url)")
    let session = URLSession.shared
    
    var urlRequest = URLRequest(url: url)
    urlRequest.addValue(userAgent, forHTTPHeaderField: "User-Agent")
    
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

PlaygroundPage.current.setLiveView(ContentView())
