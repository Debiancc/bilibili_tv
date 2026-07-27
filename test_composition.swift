import Foundation
import AVFoundation

let videoURLStr = "https://upos-sz-mirror08h.bilivideo.com/upgcxcode/64/50/40185955064/40185955064_sr1-1-100035.m4s?e=ig8euxZM2rNcNbdlhoNvNC8BqJIzNbfqXBvEqxTEto8BTrNvN0GvT90W5JZMkX_YN0MvXg8gNEV4NC8xNEV4N03eN0B5tZlqNxTEto8BTrNvNeZVuJ10Kj_g2UB02J0mN0B5tZlqNCNEto8BTrNvNC7MTX502C8f2jmMQJ6mqF2fka1mqx6gqj0eN0B599M=&os=08hbv&og=hw&nbs=1&uipk=5&mid=286552227&gen=playurlv3&oi=2071561970&trid=5b38ea2cbceb4805ba6f91a70093554p&platform=pc&deadline=1785075182&upsig=bd7c73f56859f3ccb3975e458fa06162&uparams=e,os,og,nbs,uipk,mid,gen,oi,trid,platform,deadline&bvc=vod&nettype=0&bw=9403729&lrs=0&build=0&dl=0&f=p_0_0&allo_id=&qn_dyeid=&agrr=0&buvid=&orderid=0,3"

let headers = ["Referer": "https://www.bilibili.com", "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"]
let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]

let videoAsset = AVURLAsset(url: URL(string: videoURLStr)!, options: options)

let sem = DispatchSemaphore(value: 0)

Task {
    do {
        print("Loading tracks...")
        let tracks = try await videoAsset.loadTracks(withMediaType: .video)
        print("Successfully loaded \(tracks.count) video tracks!")
        if let track = tracks.first {
            let duration = try await track.load(.timeRange)
            print("Track duration: \(duration.duration.seconds) seconds")
        }
    } catch {
        print("Error loading tracks: \(error)")
    }
    sem.signal()
}

sem.wait()
