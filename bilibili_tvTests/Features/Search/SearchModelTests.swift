//
//  SearchModelTests.swift
//  bilibili_tvTests
//
//  搜索模型解码契约测试：锁定 search/all/v2 响应解析语义，
//  重点验证 PGC 分组过滤与 `<em>` 高亮标签清理。
//

import Foundation
import Testing

@testable import bilibili_tv

struct SearchModelTests {
    // MARK: - 解码契约

    @Test func decodeFullResponse_filtersPGCOnly() throws {
        let json = """
            {
              "code": 0,
              "message": "0",
              "data": {
                "result": [
                  {
                    "result_type": "video",
                    "data": [{ "type": "video", "aid": 1, "title": "UP主视频" }]
                  },
                  {
                    "result_type": "media_bangumi",
                    "data": [{
                      "season_id": 40307,
                      "title": "<em class=\\"keyword\\">测试</em>番剧",
                      "cover": "//i0.hdslb.com/bfs/bangumi/image/x.jpg",
                      "styles": "悬疑/剧情",
                      "score": 9.6,
                      "areas": [{ "name": "日本" }],
                      "goto": "bangumi"
                    }]
                  },
                  {
                    "result_type": "media_ft",
                    "data": [{
                      "season_id": 40308,
                      "title": "<em class=\\"keyword\\">测试</em>电影",
                      "cover": "//i0.hdslb.com/bfs/bangumi/image/y.jpg",
                      "styles": "剧情/家庭",
                      "score": 8.8,
                      "areas": ["中国"],
                      "goto": "movie"
                    }]
                  },
                  {
                    "result_type": "bili_user",
                    "data": [{ "mid": 1, "uname": "用户" }]
                  }
                ],
                "numResults": 123,
                "pages": 7
              }
            }
            """

        let data = try JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: Data(json.utf8)))
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)

        #expect(response.code == 0)
        let sections = try #require(response.data?.sections)
        #expect(sections.count == 4)
        #expect(sections.filter(\.isPGC).count == 2)
        #expect(sections.filter(\.isPGC).allSatisfy { $0.title == "番剧" || $0.title == "影视" })

        let bangumi = try #require(sections.first { $0.resultType == "media_bangumi" }?.items.first)
        #expect(bangumi.seasonId == 40_307)
        #expect(bangumi.plainTitle == "测试番剧")
        #expect(bangumi.score == 9.6)
        #expect(bangumi.styles == "悬疑/剧情")
    }

    @Test func decodeMissingOptionalFields_defaultsSafely() throws {
        let json = """
            {
              "code": 0,
              "message": null,
              "data": {
                "result": [
                  { "result_type": "media_ft", "data": [{ "season_id": 1 }] }
                ]
              }
            }
            """

        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))
        let section = try #require(response.data?.sections.first)
        #expect(section.isPGC)
        #expect(section.items.first?.plainTitle == nil)
        #expect(section.items.first?.areas.isEmpty ?? false)
    }

    @Test func decodeEmptyResult_defaultsEmpty() throws {
        let json = #"{"code": 0, "message": "0", "data": {"result": null}}"#
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))
        #expect(response.data?.sections.isEmpty ?? false)
    }

    // MARK: - 高亮标签清理

    @Test func plainTitle_stripsEmAndEntities() {
        let item = SearchResultItem(
            seasonId: 1,
            episodeId: nil,
            title: "<em class=\"keyword\">A&amp;B</em> 电影",
            cover: nil,
            styles: nil,
            score: nil,
            areas: [],
            goto: nil,
            desc: nil
        )
        #expect(item.plainTitle == "A&B 电影")
    }

    // MARK: - FeedItem 映射

    @Test func feedItemMapping_preservesNavFields() {
        let item = SearchResultItem(
            seasonId: 40_307,
            episodeId: nil,
            title: "测试番剧",
            cover: "//i0.hdslb.com/bfs/bangumi/image/x.jpg",
            styles: "悬疑/剧情",
            score: 9.6,
            areas: ["日本"],
            goto: "bangumi",
            desc: "简介"
        )
        let feed = item.feedItem
        #expect(feed.seasonId == 40_307)
        #expect(feed.title == "测试番剧")
        #expect(feed.subtitle == "悬疑/剧情")
        #expect(feed.rating == "9.6")
        #expect(feed.brief == "简介")
    }
}
