import Foundation
import Testing

@testable import GitKit

@Suite("危险操作预警")
struct HazardWarningTests {

    @Test("安全操作不预警")
    func safeOperationsHaveNoWarning() {
        // 把「暂存一个文件」也做成需要确认，只会让人养成闭眼点确定的习惯，
        // 等真正危险的那次也照点不误
        for operation in [
            GitOperation.stage(paths: ["a.txt"]),
            GitOperation.unstage(paths: ["a.txt"]),
            GitOperation.commit(message: "x"),
            GitOperation.switchBranch(to: "main"),
        ] {
            #expect(!operation.needsWarning)
            #expect(operation.warning(hasSnapshot: true) == nil)
        }
    }

    @Test("丢弃未提交改动是唯一真正找不回来的一类")
    func discardIsDestructive() throws {
        let operation = GitOperation.discard(paths: ["a.txt"])
        #expect(operation.hazard == .discardsUncommittedWork)

        let warning = try #require(operation.warning(hasSnapshot: false))
        #expect(warning.isDestructive)
        // 必须点明 reflog 也救不回来——这正是它和改写历史的本质区别
        #expect(warning.consequence.contains("reflog"))
        #expect(warning.recovery.contains("没有任何退路"))
    }

    @Test("有快照时「怎么退回来」的答案完全不同")
    func snapshotChangesRecoveryAdvice() throws {
        let operation = GitOperation.discard(paths: ["a.txt"])

        let without = try #require(operation.warning(hasSnapshot: false))
        let with = try #require(operation.warning(hasSnapshot: true))

        #expect(without.recovery != with.recovery)
        #expect(with.recovery.contains("时间线"))
    }

    @Test("改写历史会提醒 hash 变化与推送后果")
    func rewriteWarnsAboutHashChange() throws {
        let operation = GitOperation.interactiveRebase(
            base: "HEAD~3", summary: "整理最近 3 条提交", backupTag: nil)
        #expect(operation.hazard == .rewritesHistory)

        let warning = try #require(operation.warning(hasSnapshot: true))
        #expect(warning.consequence.contains("commit hash"))
        #expect(warning.consequence.contains("推送"))
        // 改写历史不是「找不回来」——reflog 还在，所以不标红
        #expect(!warning.isDestructive)
    }

    @Test("确认按钮写的是动作而不是「确定」")
    func confirmLabelDescribesAction() throws {
        // 让人在点之前再读一遍自己要做什么
        let operation = GitOperation.discard(paths: ["a.txt", "b.txt"])
        let warning = try #require(operation.warning(hasSnapshot: true))

        #expect(warning.confirmLabel == operation.summary)
        #expect(warning.confirmLabel != "确定")
    }

    @Test("预警里始终带着等价的 git 命令")
    func warningCarriesEquivalentCommand() throws {
        // 透明命令层贯穿到预警层：越是危险的一步，越该让人看清它到底是什么
        let operation = GitOperation.discard(paths: ["a.txt"])
        let warning = try #require(operation.warning(hasSnapshot: true))

        #expect(warning.equivalentCommand == operation.equivalentCommand)
        #expect(warning.equivalentCommand.hasPrefix("git "))
    }

    @Test("每条预警都完整回答三个问题")
    func everyWarningAnswersThreeQuestions() throws {
        // 会发生什么、能不能撤销、怎么撤销——缺一个用户就得自己猜
        let dangerous = [
            GitOperation.discard(paths: ["a"]),
            GitOperation.interactiveRebase(base: "HEAD~1", summary: "整理", backupTag: nil),
        ]

        for operation in dangerous {
            for hasSnapshot in [true, false] {
                let warning = try #require(operation.warning(hasSnapshot: hasSnapshot))
                #expect(!warning.title.isEmpty)
                #expect(!warning.consequence.isEmpty)
                #expect(!warning.recovery.isEmpty)
                #expect(!warning.confirmLabel.isEmpty)
            }
        }
    }
}

@Suite("新手引导")
struct OnboardingTests {

    @Test("引导按真实工作流排序，不按概念体系")
    func toursFollowWorkflowOrder() {
        // 先看改了什么，再挑要提交的，然后提交、推送——
        // 按 Git 的概念体系排（对象模型 → 引用 → 工作流）没有人能读下去
        let ids = OnboardingStep.repositoryTour.map(\.id)
        #expect(ids == ["changes", "stage", "commit", "history", "timeline", "palette"])
    }

    @Test("每一步都说清界面上在哪、能做什么")
    func everyStepHasTitleAndDetail() {
        for step in OnboardingStep.repositoryTour {
            #expect(!step.title.isEmpty)
            #expect(!step.detail.isEmpty)
        }
    }

    @Test("概念解释挂在用到它的那一步旁边")
    func conceptsAttachToRelevantStep() throws {
        // 「暂存区」这个概念只在讲暂存时出现，不做成一份术语表
        let stage = try #require(OnboardingStep.repositoryTour.first { $0.id == "stage" })
        #expect(stage.concept?.contains("暂存区") == true)

        let commit = try #require(OnboardingStep.repositoryTour.first { $0.id == "commit" })
        #expect(commit.concept?.contains("提交") == true)
    }

    @Test("时间线那一步点明这是 git 本身做不到的")
    func timelineStepExplainsTheDifference() throws {
        let timeline = try #require(OnboardingStep.repositoryTour.first { $0.id == "timeline" })
        #expect(timeline.concept?.contains("做不到") == true)
    }
}
