import XCTest
@testable import FluxIPTVCore

final class CatalogIndexTests: XCTestCase {
    private let source = UUID()
    private func item(_ i: Int, kind: IPTVMediaKind = .movie, group: String = "France", name: String? = nil) -> IPTVItem {
        IPTVItem(id:"\(kind.rawValue)-\(i)",sourceID:source,name:name ?? "Film \(i)",group:group,logoURL:nil,kind:kind,directURL:nil,xtreamStreamID:String(i),fileExtension:"mp4")
    }
    func testKindGroupSearchAndFavorites() throws {
        let one = item(1,name:"Été à Paris"), two = item(2,group:"Québec",name:"Automne"), live = item(3,kind:.live)
        let index = CatalogIndex([one,two,live,one])
        XCTAssertEqual(index.items.count,3)
        XCTAssertEqual(index.unfiltered(.movie).all.items.map(\.id),[one.id,two.id])
        XCTAssertEqual(index.unfiltered(.movie).slice(group:"Québec").items,[two])
        XCTAssertEqual(try index.matching(kind:.movie,search:"ete").all.items,[one])
        XCTAssertEqual(try index.matching(kind:.movie,search:"quebec").all.items,[two])
        XCTAssertEqual(try index.matching(kind:.movie,search:"",membership:[live.id,two.id]).all.items,[two])
        XCTAssertTrue(try index.matching(kind:.movie,search:"inexistant").all.items.isEmpty)
        XCTAssertEqual(index.item(id:live.id),live)
    }
    func testPagingAndHistoryKeepOrder() {
        let slice = CatalogSlice((0..<145).map { item($0) })
        XCTAssertEqual(slice.pageCount(size:64),3)
        XCTAssertEqual(slice.window(page:2,size:64).count,17)
        XCTAssertEqual(slice.window(page:999,size:64).last?.id,"movie-144")
        XCTAssertEqual(slice.page(for:"movie-64",size:64),1)
        XCTAssertEqual(slice.retaining(ids:["movie-144","movie-3","movie-60","missing"]).items.map(\.id),["movie-3","movie-60","movie-144"])
        XCTAssertTrue(CatalogSlice().window(page:100,size:64).isEmpty)
    }
    func testVirtualGridMatchesOldFocusAlgorithm() {
        let slice = CatalogSlice((0..<23).map { item($0) })
        let prefix = [["header-a","header-b"],["filter"],[]]
        let ids = slice.items.map(\.id)
        for columns in [1,2,5,23] {
            let rows = prefix + stride(from:0,to:ids.count,by:columns).map { Array(ids[$0..<min($0+columns,ids.count)]) }
            for id in ids + prefix.flatMap({$0}) + ["missing"] {
                for direction in [RemoteAction.up,.down,.left,.right,.select] {
                    XCTAssertEqual(slice.move(from:id,action:direction,prefix:prefix,columns:columns),RemoteNavigation.move(from:id,action:direction,rows:rows),"\(id) \(direction) \(columns)")
                }
            }
        }
    }
    func testSixtyThousandTitlesRemainAddressableAcrossPages() throws {
        let indexStart = Date()
        let index = CatalogIndex((0..<60_000).map { item($0,group:"Rayon \($0 % 120)") })
        let slice = index.unfiltered(.movie).all
        let indexingMS = Date().timeIntervalSince(indexStart)*1000
        XCTAssertEqual(slice.items.count,60_000)
        XCTAssertEqual(slice.pageCount(size:64),938)
        XCTAssertEqual(slice.window(page:937,size:64).count,32)
        XCTAssertEqual(slice.move(from:"movie-63",action:.right,prefix:[],columns:slice.items.count),"movie-64")
        let start = Date()
        var id: String? = "movie-0"
        for _ in 0..<59_999 { id=slice.move(from:id,action:.right,prefix:[["header"]],columns:slice.items.count) }
        let elapsedMS=Date().timeIntervalSince(start)*1000
        XCTAssertEqual(id,"movie-59999")
        XCTAssertEqual(slice.page(for:id!,size:64),937)
        print(String(format:"CATALOG BENCH (Linux XCTest, debug): 60000 titres indexés en %.2f ms (génération incluse), 59999 déplacements en %.2f ms",indexingMS,elapsedMS))
    }
}

extension CatalogIndexTests {
    func testCompleteCatalogScopeNeverMeansHistoryOrPreset() {
        XCTAssertTrue(CatalogScope.isAll(group:nil,search:"  ",presetID:nil,resumeOnly:false))
        XCTAssertFalse(CatalogScope.isAll(group:nil,search:"",presetID:nil,resumeOnly:true))
        XCTAssertFalse(CatalogScope.isAll(group:nil,search:"",presetID:"favorite",resumeOnly:false))
        XCTAssertFalse(CatalogScope.isAll(group:"France",search:"",presetID:nil,resumeOnly:false))
        XCTAssertFalse(CatalogScope.isAll(group:nil,search:"Aladdin",presetID:nil,resumeOnly:false))
        let full=CatalogSlice((0..<150).map{item($0)})
        let history=full.retaining(ids:["movie-12","movie-100"])
        XCTAssertEqual(history.items.count,2)
        XCTAssertEqual(full.items.count,150)
        XCTAssertEqual(full.window(page:0,size:60).count,60)
        XCTAssertEqual(full.window(page:2,size:60).count,30)
    }
    func testInspectionCrossesGridPagesAndKeepsNeighborsFromSelectedScope() {
        let full=CatalogSlice((0..<150).map{item($0)})
        let selected=full.items[59]
        let opened=full.inspection(containing:selected,fallback:CatalogSlice())
        XCTAssertEqual(opened.adjacent(to:selected.id,offset:-1)?.id,"movie-58")
        XCTAssertEqual(opened.adjacent(to:selected.id,offset:1)?.id,"movie-60")
        XCTAssertEqual(opened.page(for:"movie-60",size:60),1)
        XCTAssertNil(opened.adjacent(to:"movie-0",offset:-1))
        XCTAssertNil(opened.adjacent(to:"movie-149",offset:1))
        XCTAssertNil(opened.adjacent(to:"movie-149",offset:Int.max))
        let filtered=full.retaining(ids:["movie-59","movie-90","movie-140"])
        let filteredOpen=filtered.inspection(containing:selected,fallback:full)
        XCTAssertEqual(filteredOpen.adjacent(to:selected.id,offset:1)?.id,"movie-90")
        XCTAssertEqual(filteredOpen.items.count,3)
        let fallback=CatalogSlice().inspection(containing:selected,fallback:full)
        XCTAssertEqual(fallback.items.count,150)
        let single=CatalogSlice().inspection(containing:selected,fallback:CatalogSlice())
        XCTAssertEqual(single.items,[selected])
    }
}
