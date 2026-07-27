import Foundation

let urlStr = "https://upos-sz-mirror08h.bilivideo.com/upgcxcode/64/50/40185955064/40185955064_sr1-1-100035.m4s?e=ig8euxZM2rNcNbdlhoNvNC8BqJIzNbfqXBvEqxTEto8BTrNvN0GvT90W5JZMkX_YN0MvXg8gNEV4NC8xNEV4N03eN0B5tZlqNxTEto8BTrNvNeZVuJ10Kj_g2UB02J0mN0B5tZlqNCNEto8BTrNvNC7MTX502C8f2jmMQJ6mqF2fka1mqx6gqj0eN0B599M=&os=08hbv&og=hw&nbs=1&uipk=5&mid=286552227&gen=playurlv3&oi=2071561970&trid=5b38ea2cbceb4805ba6f91a70093554p&platform=pc&deadline=1785075182&upsig=bd7c73f56859f3ccb3975e458fa06162&uparams=e,os,og,nbs,uipk,mid,gen,oi,trid,platform,deadline&bvc=vod&nettype=0&bw=9403729&lrs=0&build=0&dl=0&f=p_0_0&allo_id=&qn_dyeid=&agrr=0&buvid=&orderid=0,3"

var req = URLRequest(url: URL(string: urlStr)!)
req.setValue("bytes=0-932", forHTTPHeaderField: "Range")
req.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

let sem = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: req) { data, res, err in
    defer { sem.signal() }
    guard let data = data else { print("No data"); return }
    print("Received \(data.count) bytes")
    
    // Parse ftyp
    var offset = 0
    func read32() -> UInt32 {
        let val = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
        offset += 4
        return val
    }
    
    let size = read32()
    let type = read32()
    
    guard type == 0x66747970 /* ftyp */ else {
        print("Not ftyp box")
        return
    }
    
    let majorBrand = String(data: data.subdata(in: offset..<offset+4), encoding: .ascii) ?? ""
    offset += 4
    let minorVersion = read32()
    
    print("ftyp majorBrand: \(majorBrand), minorVersion: \(minorVersion)")
    
    var compBrands = [String]()
    while offset < size {
        if let brand = String(data: data.subdata(in: offset..<offset+4), encoding: .ascii) {
            compBrands.append(brand)
        }
        offset += 4
    }
    
    print("compatibleBrands: \(compBrands)")
}.resume()

sem.wait()
