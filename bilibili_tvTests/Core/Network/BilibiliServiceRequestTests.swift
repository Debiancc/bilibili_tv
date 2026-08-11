//
//  BilibiliServiceRequestTests.swift
//  bilibili_tvTests
//
//  BilibiliService.requestData 冒烟测试：
//  - 统一 Header/Cookie 注入确实作用于每次请求
//  - GET/POST/body/contentType 正确落到 URLRequest
//  - 200 返回原始 Data，非 2xx 抛 URLError(.badServerResponse)，非法 URL 抛 URLError(.badURL)
//  - execute/executeData 路由到同一 requestData
//

import Foundation
import Testing

@testable import bilibili_tv

/// 拦截所有请求并按脚本返回预置响应 (用于替换真实网络)
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct BilibiliServiceRequestTests {
    private func makeService() -> BilibiliService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return BilibiliService(session: session)
    }

    private func respond(status: Int, data: Data = Data()) throws -> (HTTPURLResponse, Data) {
        let response = try #require(HTTPURLResponse(url: URL(string: "https://api.bilibili.com/ok")!, statusCode: status, httpVersion: nil, headerFields: nil))
        return (response, data)
    }

    // MARK: - 统一 Header 注入

    @Test func requestData_injectsCommonHeaders() async throws {
        let service = makeService()
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return try self.respond(status: 200, data: Data("ok".utf8))
        }

        _ = try await service.requestData(urlString: "https://api.bilibili.com/x/tv/modpage_v2")

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "accept") == "application/json, text/plain, */*")
        #expect(request.value(forHTTPHeaderField: "referer") == "https://www.bilibili.com/")
        #expect(request.value(forHTTPHeaderField: "user-agent") != nil)
        #expect(request.value(forHTTPHeaderField: "cookie") != nil)
    }

    @Test func requestData_appliesQueryItems() async throws {
        let service = makeService()
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return try self.respond(status: 200)
        }

        _ = try await service.requestData(
            urlString: "https://api.bilibili.com/x/tv/modpage_v2",
            queryItems: [URLQueryItem(name: "page_id", value: "531")]
        )

        let url = try #require(capturedRequest?.url)
        #expect(url.absoluteString.contains("page_id=531"))
    }

    // MARK: - HTTP 语义

    @Test func requestData_postWithBodyAndContentType() async throws {
        let service = makeService()
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return try self.respond(status: 200, data: Data("{}".utf8))
        }

        _ = try await service.requestData(
            urlString: "https://api.bilibili.com/x/click-interface/web/heartbeat",
            method: "POST",
            body: Data("a=1".utf8),
            contentType: "application/x-www-form-urlencoded"
        )

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let bodyData = try request.httpBody ?? drainBodyStream(request)
        #expect(bodyData == Data("a=1".utf8))
    }

    /// URLSession 在进入 URLProtocol 前会把 httpBody 转成 httpBodyStream，这里兜底读取
    private func drainBodyStream(_ request: URLRequest) throws -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4_096)
            if read < 0 { break }
            if read == 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    @Test func requestData_defaultMethodIsGET() async throws {
        let service = makeService()
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return try self.respond(status: 200)
        }

        _ = try await service.requestData(urlString: "https://api.bilibili.com/ok")

        #expect(capturedRequest?.httpMethod == "GET")
    }

    // MARK: - 状态码校验

    @Test func requestData_200ReturnsData() async throws {
        let service = makeService()
        MockURLProtocol.requestHandler = { _ in
            try self.respond(status: 200, data: Data("payload".utf8))
        }

        let data = try await service.requestData(urlString: "https://api.bilibili.com/ok")

        #expect(String(data: data, encoding: .utf8) == "payload")
    }

    @Test func requestData_non2xxThrowsBadServerResponse() async throws {
        let service = makeService()
        MockURLProtocol.requestHandler = { _ in
            try self.respond(status: 500)
        }

        await #expect(throws: URLError.self) {
            _ = try await service.requestData(urlString: "https://api.bilibili.com/ok")
        }
    }

    @Test func requestData_invalidURLThrowsBadURL() async throws {
        let service = makeService()
        MockURLProtocol.requestHandler = { _ in
            try self.respond(status: 200)
        }

        await #expect(throws: URLError.self) {
            _ = try await service.requestData(urlString: "http://%zz")
        }
    }

    // MARK: - execute / executeData 路由

    @Test func execute_decodesThroughRequestData() async throws {
        struct DecodablePayload: Decodable {
            let value: Int
        }

        let service = makeService()
        MockURLProtocol.requestHandler = { _ in
            try self.respond(status: 200, data: Data(#"{"value":42}"#.utf8))
        }

        let decoded: DecodablePayload = try await service.execute(urlString: "https://api.bilibili.com/ok")

        #expect(decoded.value == 42)
    }

    @Test func executeData_returnsRawBytes() async throws {
        let service = makeService()
        let raw = Data([0xDE, 0xAD, 0xBE, 0xEF])
        MockURLProtocol.requestHandler = { _ in
            try self.respond(status: 200, data: raw)
        }

        let data = try await service.executeData(urlString: "https://api.bilibili.com/x/v2/dm/list/seg.so")

        #expect(data == raw)
    }
}
