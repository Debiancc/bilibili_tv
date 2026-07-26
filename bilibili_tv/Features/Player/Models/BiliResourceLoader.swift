import Foundation
import AVFoundation

/// 解决 Bilibili CDN 35 秒强制断连 (HTTP 303) 和加载缓慢的资源加载代理
final class BiliResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    
    private let videoURL: URL
    private let audioURL: URL?
    private let headers: [String: String]
    
    private var session: URLSession!
    private var pendingRequests = [AVAssetResourceLoadingRequest: ResourceRequestState]()
    private let queue = DispatchQueue(label: "com.bilibili.resourceloader", attributes: .concurrent)
    
    init(videoURL: URL, audioURL: URL?, headers: [String: String]) {
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.headers = headers
        super.init()
        
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    deinit {
        session.invalidateAndCancel()
    }
    
    // MARK: - AVAssetResourceLoaderDelegate
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        
        let isVideo = url.scheme == "bili-video"
        let isAudio = url.scheme == "bili-audio"
        guard isVideo || isAudio else { return false }
        
        let targetURL = isVideo ? videoURL : audioURL!
        
        queue.async(flags: .barrier) {
            self.startRequest(loadingRequest, targetURL: targetURL)
        }
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        queue.async(flags: .barrier) {
            if let state = self.pendingRequests[loadingRequest] {
                state.task?.cancel()
                self.pendingRequests.removeValue(forKey: loadingRequest)
            }
        }
    }
    
    // MARK: - Request Management
    
    private class ResourceRequestState {
        let targetURL: URL
        let headers: [String: String]
        var task: URLSessionDataTask?
        var currentOffset: Int64
        let requestedLength: Int64
        let session: URLSession
        
        init(targetURL: URL, headers: [String: String], offset: Int64, length: Int64, session: URLSession) {
            self.targetURL = targetURL
            self.headers = headers
            self.currentOffset = offset
            self.requestedLength = length
            self.session = session
        }
    }
    
    private func startRequest(_ loadingRequest: AVAssetResourceLoadingRequest, targetURL: URL) {
        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return
        }
        
        let offset = dataRequest.requestedOffset
        let length = Int64(dataRequest.requestedLength)
        
        let state = ResourceRequestState(targetURL: targetURL, headers: headers, offset: offset, length: length, session: session)
        pendingRequests[loadingRequest] = state
        
        performNetworkRequest(for: loadingRequest, state: state)
    }
    
    private func performNetworkRequest(for loadingRequest: AVAssetResourceLoadingRequest, state: ResourceRequestState) {
        guard let dataRequest = loadingRequest.dataRequest else { return }
        
        var request = URLRequest(url: state.targetURL)
        for (k, v) in state.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        
        // 关键：计算剩余需要请求的 Range
        let bytesRemaining = state.requestedLength - (state.currentOffset - dataRequest.requestedOffset)
        let endOffset = state.currentOffset + bytesRemaining - 1
        request.setValue("bytes=\(state.currentOffset)-\(endOffset)", forHTTPHeaderField: "Range")
        
        let task = state.session.dataTask(with: request)
        state.task = task
        task.resume()
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queue.async {
            guard let (loadingRequest, _) = self.pendingRequests.first(where: { $0.value.task == dataTask }),
                  let infoRequest = loadingRequest.contentInformationRequest,
                  let httpResponse = response as? HTTPURLResponse else {
                completionHandler(.allow)
                return
            }
            
            // 填充 ContentInformation (时长、类型等)，让 AVPlayer 知道这是完整的 MP4
            let isVideo = loadingRequest.request.url?.scheme == "bili-video"
            infoRequest.contentType = isVideo ? "public.mpeg-4" : "public.mpeg-4-audio"
            infoRequest.isByteRangeAccessSupported = true
            
            // 从 Content-Range 头提取总长度 (格式: bytes 0-100/1000)
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
               let totalLengthString = contentRange.components(separatedBy: "/").last,
               let totalLength = Int64(totalLengthString) {
                infoRequest.contentLength = totalLength
            } else {
                infoRequest.contentLength = response.expectedContentLength
            }
            
            completionHandler(.allow)
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async {
            guard let (loadingRequest, state) = self.pendingRequests.first(where: { $0.value.task == dataTask }),
                  let dataRequest = loadingRequest.dataRequest else { return }
            
            dataRequest.respond(with: data)
            state.currentOffset += Int64(data.count)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async(flags: .barrier) {
            guard let (loadingRequest, state) = self.pendingRequests.first(where: { $0.value.task == task }) else { return }
            
            if let error = error {
                let nsError = error as NSError
                // 处理 Bilibili CDN 强制断开的 HTTP/2 错误 (通常是 URLError.networkConnectionLost 或 code 303)
                if nsError.domain == NSURLErrorDomain || nsError.code == 303 || nsError.code == -1005 {
                    let requestedEndOffset = loadingRequest.dataRequest!.requestedOffset + Int64(loadingRequest.dataRequest!.requestedLength)
                    if state.currentOffset < requestedEndOffset {
                        print("♻️ [ResourceLoader] Connection dropped at offset \(state.currentOffset). Resuming fetch...")
                        self.performNetworkRequest(for: loadingRequest, state: state)
                        return
                    }
                }
                print("❌ [ResourceLoader] Task failed: \(error)")
                loadingRequest.finishLoading(with: error)
            } else {
                loadingRequest.finishLoading()
            }
            
            self.pendingRequests.removeValue(forKey: loadingRequest)
        }
    }
}
