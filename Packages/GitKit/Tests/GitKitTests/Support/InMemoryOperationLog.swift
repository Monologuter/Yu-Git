import Foundation

@testable import GitKit

/// 测试用的内存操作日志，免去落盘与清理。
actor InMemoryOperationLog: OperationLogging {

    private(set) var records: [OperationRecord] = []

    func record(_ record: OperationRecord) {
        records.append(record)
    }

    func recent(limit: Int) -> [OperationRecord] {
        Array(records.suffix(limit))
    }
}
