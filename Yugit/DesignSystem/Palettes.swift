import AppKit
import SwiftUI

// 墨 / 昼 / 谱 三套主题。
//
// 结构和 ``SystemTheme`` 完全一样，只换数值——那边写了每一组为什么这么分、
// 每个 token 管什么，这里不重复，只记各自的取舍。
//
// 三套共同守着和默认主题一样的三条硬约束：
// 1. 红与绿被 diff 独占，8 条轨道与语法色一律避开这两个色相
// 2. 强调色是用户在系统设置里的选择，主题不碰它
// 3. 品牌色靠**明度**而不是色相跟轨道区分——每一套的品牌色都比该套所有轨道更深
//
// 每套都在设计阶段实测过：正文对比度、diff 双层底叠加后的可读性、
// 相邻轨道在三种色觉模拟下的最小 ΔE。数值见 `design/驭Git/tokens/themes.css` 的注释。

/// 墨：长时间连续使用。
///
/// 低对比暖调，非重点元素明显后退。轨道色度压到默认的 0.82 倍——
/// 相邻轨道最小 ΔE 6.9，是六组里最松的一组，这是「后退」的代价，也是它的目的：
/// 盯着看六到八个小时时，一张不抢眼的图比一张精确的图更重要。
struct InkTheme: ThemePalette {

    let identifier = "mo"
    let displayName = "墨"
    let summary = "低对比暖调，非重点元素明显后退，适合一天连着盯几个小时"

    var accent: Color { .accentColor }
    var onAccent: Color { Color(nsColor: .alternateSelectedControlTextColor) }

    var brand: Color { .theme(light: 0x51_4A88, dark: 0x85_7FC3) }
    var brandHover: Color { .theme(light: 0x41_3976, dark: 0x9A_95DA) }
    var brandWash: Color { .theme(light: 0xF1_F1FF, dark: 0x2A_2841) }
    var onBrand: Color { .theme(light: 0xFF_FFFF, dark: 0x13_1221) }

    var contentBackground: Color { .theme(light: 0xFA_F6EF, dark: 0x1E_1914) }
    var sunkenBackground: Color { .theme(light: 0xF2_EEE7, dark: 0x14_100B) }
    var raisedBackground: Color { .theme(light: 0xFE_FBF6, dark: 0x26_231F) }
    var hoverBackground: Color { .theme(light: 0xE9_E4DC, dark: 0x31_2B24) }
    var fillQuaternary: Color { .theme(light: 0xEC_E7DF, dark: 0x33_2D26) }

    var primaryText: Color { .theme(light: 0x3C_3730, dark: 0xCB_C3BB) }
    var secondaryText: Color { .theme(light: 0x68_625A, dark: 0x97_9189) }
    var tertiaryText: Color { .theme(light: 0x76_6F68, dark: 0x89_827A) }
    var decorativeText: Color { .theme(light: 0xA2_9C96, dark: 0x5A_5650) }

    var separator: Color { .theme(light: 0xDB_D6CF, dark: 0x39_332D) }
    var separatorStrong: Color { .theme(light: 0xC0_BBB4, dark: 0x53_4D47) }

    var warning: Color { .theme(light: 0x95_601E, dark: 0xB1_7C3D) }
    var warningWash: Color { .theme(light: 0xFF_EAD3, dark: 0x3C_270F) }
    var success: Color { .theme(light: 0x2A_7A47, dark: 0x47_9560) }
    var mergeAccent: Color { .theme(light: 0x82_58AF, dark: 0x9E_73CC) }

    var lanes: [NSColor] {
        [
            .theme(light: 0x30_8279, dark: 0x42_ACA0),  // 1 靛青
            .theme(light: 0xAA_66EC, dark: 0xCC_ABF4),  // 2 紫
            .theme(light: 0x93_6A2A, dark: 0xC2_8D3A),  // 3 琥
            .theme(light: 0x3B_9BB8, dark: 0x52_CDF3),  // 4 蓝
            .theme(light: 0xB8_3396, dark: 0xF0_49C5),  // 5 玫
            .theme(light: 0x9A_9036, dark: 0xCC_BF4A),  // 6 柘
            .theme(light: 0x36_66E7, dark: 0x6E_95EE),  // 7 靛
            .theme(light: 0xDB_6635, dark: 0xF5_A688),  // 8 赭
        ]
    }
    var laneOnSelection: NSColor { .white }
    var laneNodeCore: NSColor { .theme(light: 0xFA_F6EF, dark: 0x1E_1914) }
    var laneNodeCoreOnSelection: NSColor { .selectedContentBackgroundColor }
    var laneLineWidth: CGFloat { 2.5 }
    var laneNodeRadius: CGFloat { 4.5 }

    var diffAddedText: Color { .theme(light: 0x23_7742, dark: 0x57_A76F) }
    var diffDeletedText: Color { .theme(light: 0xAF_4440, dark: 0xE3_726C) }
    var diffAddedLine: Color { .theme(light: 0xDF_FAE5, dark: 0x15_2D1C) }
    var diffDeletedLine: Color { .theme(light: 0xFF_EDEB, dark: 0x3A_1E1C) }
    var diffAddedWord: Color { .theme(light: 0xB6_F1C4, dark: 0x04_4822) }
    var diffDeletedWord: Color { .theme(light: 0xFF_D4CF, dark: 0x62_2522) }
    var conflict: Color { .theme(light: 0x95_601E, dark: 0xB1_7C3D) }
    var danger: Color { .theme(light: 0xB7_4744, dark: 0xD6_635D) }

    var syntaxKeyword: Color { .theme(light: 0x73_479F, dark: 0xA5_79D4) }
    var syntaxString: Color { .theme(light: 0x8B_4C27, dark: 0xBF_7D57) }
    var syntaxComment: Color { .theme(light: 0x81_7A73, dark: 0x7D_766F) }
    var syntaxNumber: Color { .theme(light: 0x83_5107, dark: 0xB7_8144) }
    var syntaxType: Color { .theme(light: 0x00_675F, dark: 0x42_9B90) }
}

/// 昼：强光环境与投屏演示。
///
/// 六组里对比最高的一套，也是唯一把「色盲友好」当设计目标的：
/// 轨道的两档明度差从 0.09 拉到 0.155，相邻最小 ΔE 13.0，
/// 且最细的那根线也过 3:1。分隔线明显到投影仪上仍看得见。
struct DaylightTheme: ThemePalette {

    let identifier = "zhou"
    let displayName = "昼"
    let summary = "最高对比，边框明确，色盲友好，适合强光环境与投屏"

    var accent: Color { .accentColor }
    var onAccent: Color { Color(nsColor: .alternateSelectedControlTextColor) }

    var brand: Color { .theme(light: 0x42_3384, dark: 0x8E_86D8) }
    var brandHover: Color { .theme(light: 0x33_2271, dark: 0xA3_9BEF) }
    var brandWash: Color { .theme(light: 0xF1_F1FF, dark: 0x1A_182F) }
    var onBrand: Color { .theme(light: 0xFF_FFFF, dark: 0x13_1221) }

    var contentBackground: Color { .theme(light: 0xFF_FFFF, dark: 0x09_0B0C) }
    var sunkenBackground: Color { .theme(light: 0xF1_F3F5, dark: 0x03_0405) }
    var raisedBackground: Color { .theme(light: 0xFF_FFFF, dark: 0x16_1718) }
    var hoverBackground: Color { .theme(light: 0xDC_DEE0, dark: 0x20_2224) }
    var fillQuaternary: Color { .theme(light: 0xE0_E2E4, dark: 0x23_2527) }

    var primaryText: Color { .theme(light: 0x0F_1112, dark: 0xE5_E7EA) }
    var secondaryText: Color { .theme(light: 0x4E_5153, dark: 0xA3_A6A8) }
    var tertiaryText: Color { .theme(light: 0x5C_5E61, dark: 0x92_9497) }
    var decorativeText: Color { .theme(light: 0x8E_9093, dark: 0x60_6164) }

    var separator: Color { .theme(light: 0xB6_B8BA, dark: 0x3D_3F41) }
    var separatorStrong: Color { .theme(light: 0x85_8688, dark: 0x63_6567) }

    var warning: Color { .theme(light: 0x9F_630C, dark: 0xAD_7021) }
    var warningWash: Color { .theme(light: 0xFF_EAD3, dark: 0x2A_1600) }
    var success: Color { .theme(light: 0x1E_8246, dark: 0x2F_8E52) }
    var mergeAccent: Color { .theme(light: 0x8B_59BE, dark: 0x98_67CC) }

    var lanes: [NSColor] {
        [
            .theme(light: 0x00_7268, dark: 0x00_9B8F),  // 1 靛青
            .theme(light: 0xB2_5AFF, dark: 0xD5_B1FF),  // 2 紫
            .theme(light: 0x84_5800, dark: 0xB3_7900),  // 3 琥
            .theme(light: 0x00_9FC3, dark: 0x4E_D6FF),  // 4 蓝
            .theme(light: 0xA9_0087, dark: 0xE4_00B7),  // 5 玫
            .theme(light: 0x9F_9200, dark: 0xD9_C700),  // 6 柘
            .theme(light: 0x11_39FF, dark: 0x48_7BFF),  // 7 靛
            .theme(light: 0xEC_5900, dark: 0xFF_AD8D),  // 8 赭
        ]
    }
    var laneOnSelection: NSColor { .white }
    var laneNodeCore: NSColor { .theme(light: 0xFF_FFFF, dark: 0x09_0B0C) }
    var laneNodeCoreOnSelection: NSColor { .selectedContentBackgroundColor }
    var laneLineWidth: CGFloat { 2.5 }
    var laneNodeRadius: CGFloat { 4.5 }

    var diffAddedText: Color { .theme(light: 0x00_6631, dark: 0x49_A768) }
    var diffDeletedText: Color { .theme(light: 0xA2_2629, dark: 0xEC_6C65) }
    var diffAddedLine: Color { .theme(light: 0xD1_FFDC, dark: 0x00_1D09) }
    var diffDeletedLine: Color { .theme(light: 0xFF_EDEB, dark: 0x30_0505) }
    var diffAddedWord: Color { .theme(light: 0x94_FAB1, dark: 0x00_3416) }
    var diffDeletedWord: Color { .theme(light: 0xFF_D4CF, dark: 0x55_0007) }
    var conflict: Color { .theme(light: 0x9F_630C, dark: 0xAD_7021) }
    var danger: Color { .theme(light: 0xC5_4542, dark: 0xD3_524E) }

    var syntaxKeyword: Color { .theme(light: 0x7E_45B3, dark: 0xA1_69D9) }
    var syntaxString: Color { .theme(light: 0x99_4C17, dark: 0xBF_6E3E) }
    var syntaxComment: Color { .theme(light: 0x7F_8184, dark: 0x6C_6F71) }
    var syntaxNumber: Color { .theme(light: 0x8B_5400, dark: 0xB5_751D) }
    var syntaxType: Color { .theme(light: 0x00_6D64, dark: 0x02_9388) }
}

/// 谱：代码编辑器审美。
///
/// 饱和度走满，语法色是主角。底色偏冷（浅色 `#FBFCFF`、深色 `#13161D`），
/// 高饱和的语法色压在冷底上才不显脏——这是编辑器配色的老规矩。
struct SpectrumTheme: ThemePalette {

    let identifier = "pu"
    let displayName = "谱"
    let summary = "冷底配最高饱和，语法色是主角，接近代码编辑器的观感"

    var accent: Color { .accentColor }
    var onAccent: Color { Color(nsColor: .alternateSelectedControlTextColor) }

    var brand: Color { .theme(light: 0x4B_3A96, dark: 0x88_7ED7) }
    var brandHover: Color { .theme(light: 0x3C_2883, dark: 0x9C_94EE) }
    var brandWash: Color { .theme(light: 0xF1_F1FF, dark: 0x27_253D) }
    var onBrand: Color { .theme(light: 0xFF_FFFF, dark: 0x13_1221) }

    var contentBackground: Color { .theme(light: 0xFB_FCFF, dark: 0x13_161D) }
    var sunkenBackground: Color { .theme(light: 0xF1_F2F6, dark: 0x0A_0D13) }
    var raisedBackground: Color { .theme(light: 0xFF_FFFF, dark: 0x20_2227) }
    var hoverBackground: Color { .theme(light: 0xE0_E2E6, dark: 0x28_2C34) }
    var fillQuaternary: Color { .theme(light: 0xE3_E5E9, dark: 0x29_2D36) }

    var primaryText: Color { .theme(light: 0x1C_2027, dark: 0xDC_E3EF) }
    var secondaryText: Color { .theme(light: 0x53_5861, dark: 0x9C_A2AD) }
    var tertiaryText: Color { .theme(light: 0x69_6D77, dark: 0x84_8A95) }
    var decorativeText: Color { .theme(light: 0x90_939C, dark: 0x5F_636B) }

    var separator: Color { .theme(light: 0xD0_D2D5, dark: 0x33_373F) }
    var separatorStrong: Color { .theme(light: 0xAD_AFB2, dark: 0x52_5760) }

    var warning: Color { .theme(light: 0x9E_6100, dark: 0xB7_7419) }
    var warningWash: Color { .theme(light: 0xFF_EAD3, dark: 0x38_230B) }
    var success: Color { .theme(light: 0x01_8040, dark: 0x2A_9554) }
    var mergeAccent: Color { .theme(light: 0x8C_54C1, dark: 0xA1_6AD9) }

    var lanes: [NSColor] {
        [
            .theme(light: 0x00_8277, dark: 0x00_B0A2),  // 1 靛青
            .theme(light: 0xB3_5EFF, dark: 0xD5_B1FF),  // 2 紫
            .theme(light: 0x97_6500, dark: 0xCB_8900),  // 3 琥
            .theme(light: 0x00_A0C5, dark: 0x4E_D6FF),  // 4 蓝
            .theme(light: 0xC0_009A, dark: 0xFF_15CE),  // 5 玫
            .theme(light: 0xA1_9300, dark: 0xD9_C700),  // 6 柘
            .theme(light: 0x25_58FF, dark: 0x64_92FF),  // 7 靛
            .theme(light: 0xEE_5A00, dark: 0xFF_AD8D),  // 8 赭
        ]
    }
    var laneOnSelection: NSColor { .white }
    var laneNodeCore: NSColor { .theme(light: 0xFB_FCFF, dark: 0x13_161D) }
    var laneNodeCoreOnSelection: NSColor { .selectedContentBackgroundColor }
    var laneLineWidth: CGFloat { 2.5 }
    var laneNodeRadius: CGFloat { 4.5 }

    var diffAddedText: Color { .theme(light: 0x00_6F36, dark: 0x4A_B36E) }
    var diffDeletedText: Color { .theme(light: 0xB0_282B, dark: 0xFB_6F69) }
    var diffAddedLine: Color { .theme(light: 0xD5_FEDE, dark: 0x04_2B13) }
    var diffDeletedLine: Color { .theme(light: 0xFF_EDEB, dark: 0x3C_1513) }
    var diffAddedWord: Color { .theme(light: 0x9E_F8B7, dark: 0x00_441E) }
    var diffDeletedWord: Color { .theme(light: 0xFF_D4CF, dark: 0x6B_070F) }
    var conflict: Color { .theme(light: 0x9E_6100, dark: 0xB7_7419) }
    var danger: Color { .theme(light: 0xC9_3B3B, dark: 0xE2_5350) }

    var syntaxKeyword: Color { .theme(light: 0x81_3CBD, dark: 0xAD_6AEE) }
    var syntaxString: Color { .theme(light: 0x9C_4700, dark: 0xCE_7036) }
    var syntaxComment: Color { .theme(light: 0x7B_8089, dark: 0x6F_757F) }
    var syntaxNumber: Color { .theme(light: 0x89_5300, dark: 0xC3_7900) }
    var syntaxType: Color { .theme(light: 0x00_6C63, dark: 0x00_9B8E) }
}
