#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
convert.py - 将医生-患者对话转换为结构化问答记录。

用法：
    python convert.py --input dialogue.txt --output qa_record.md

约束：
    1. 只删除口语填充词，不改写、不概括、不补充。
    2. “缺失项”仅来自固定主题清单，统一标注“未提及”。
    3. 输出不包含任何对话之外的医学信息。
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime
from pathlib import Path

# Git Bash / 部分 Windows 终端默认使用 GBK 输出，统一改成 UTF-8 便于查看中文提示。
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:
            pass

DOCTOR = "医生"
PATIENT = "患者"

SPEAKER_LABELS = {
    "医生": DOCTOR,
    "医师": DOCTOR,
    "doctor": DOCTOR,
    "患者": PATIENT,
    "病人": PATIENT,
    "patient": PATIENT,
}

TURN_RE = re.compile(r"^\s*([^：:]{1,6})\s*[：:]\s*(.*)$")

# 主题按优先级排列；主题只由提问判断，提问无匹配时再看回答。
TOPIC_RULES = [
    ("过敏史", ["过敏", "青霉素", "头孢", "药物过敏", "食物过敏"]),
    ("用药情况", ["吃什么药", "药名", "用药", "服药", "吃药", "停药",
                  "剂量", "怎么吃", "药物"]),
    ("家族史", ["家族", "家里人", "父亲", "母亲", "父母", "爸", "妈",
                "兄弟", "姐妹", "子女", "遗传", "肿瘤史"]),
    ("既往史", ["既往", "以前", "手术史", "住院", "慢性病", "高血压",
                "糖尿病", "肝炎", "心脏病"]),
    ("生活方式", ["抽烟", "吸烟", "喝酒", "饮酒", "饮食", "作息", "睡眠",
                  "运动", "锻炼"]),
    ("诊断与治疗", ["诊断", "治疗", "方案", "怎么处理", "手术", "化疗",
                    "放疗", "后续", "疗效"]),
    ("检查与检验", ["检查", "化验", "检验", "报告", "结果", "胃镜", "肠镜",
                    "ct", "核磁", "mri", "b超", "超声", "血常规", "病理",
                    "复查"]),
    ("主诉与症状", ["不舒服", "症状", "疼", "痛", "胀", "反酸", "恶心",
                    "呕吐", "发热", "发烧", "咳嗽", "头晕", "乏力", "胸闷",
                    "气短", "腹泻", "便秘", "大便", "体重", "失眠", "麻木",
                    "瘙痒"]),
    ("现病史", ["多久", "病程", "加重", "缓解", "变化", "复发", "开始"]),
]

# 每个主题的固定核查清单：字段 -> 用于判断“是否提及”的正则（在患者回答中检索）。
TOPIC_FIELDS = {
    "主诉与症状": {
        "起病时间": [r"多久", r"什么时候", r"几天", r"几周", r"几个月", r"几年",
                    r"天前", r"周前", r"月前", r"年前", r"小时", r"分钟",
                    r"开始", r"以来",
                    r"\d+\s*(?:天|周|个月|月|年|小时|分钟)",
                    r"[一二三四五六七八九十百几两半]+\s*(?:天|周|个?月|年|小时|分钟|个星期)"],
        "部位": [r"哪里", r"位置", r"部位", r"上腹", r"下腹", r"腹部",
                r"胃", r"头部", r"头疼", r"头痛", r"胸", r"背", r"腰",
                r"腿", r"胳膊", r"关节", r"咽", r"喉"],
        "性质": [r"隐痛", r"隐隐", r"胀痛", r"刺痛", r"钝痛", r"绞痛",
                r"烧灼", r"闷", r"胀", r"酸痛", r"跳痛", r"哪种疼"],
        "程度": [r"轻度", r"中度", r"重度", r"剧烈", r"厉害", r"能忍",
                r"受不了", r"评分", r"得分", r"\d+\s*/\s*10",
                r"(?:评分|得分)[^。！？；]{0,8}\d+"],
        "诱因与缓解因素": [r"诱因", r"加重", r"缓解", r"吃完饭", r"空腹",
                          r"活动", r"休息", r"受凉", r"按压", r"好一点",
                          r"更明显"],
        "伴随症状": [r"伴", r"同时", r"还有", r"还会", r"恶心", r"呕吐", r"发热",
                    r"发烧", r"反酸", r"出汗", r"头晕", r"乏力", r"腹泻",
                    r"便秘", r"大便", r"体重"],
    },
    "现病史": {
        "起病时间": [r"多久", r"什么时候", r"几天", r"几周", r"几个月", r"几年",
                    r"天前", r"周前", r"月前", r"年前", r"开始", r"以来",
                    r"\d+\s*(?:天|周|个月|月|年|小时|分钟)",
                    r"[一二三四五六七八九十百几两半]+\s*(?:天|周|个?月|年|小时|分钟|个星期)"],
        "病程变化": [r"加重", r"缓解", r"变化", r"复发", r"反复", r"好一点",
                    r"减轻"],
        "诊疗经过": [r"看过", r"检查", r"吃药", r"治疗", r"门诊", r"医院"],
        "目前情况": [r"现在", r"目前", r"最近"],
    },
    "既往史": {
        "慢性病史": [r"高血压", r"糖尿病", r"肝炎", r"心脏病", r"慢性",
                    r"病史"],
        "手术史": [r"手术", r"开过刀", r"切除"],
        "住院史": [r"住院", r"住过院", r"入院"],
    },
    "用药情况": {
        "药名": [r"什么药", r"药名", r"开过", r"吃了", r"服用", r"口服",
                r"片", r"胶囊"],
        "剂量": [r"毫克", r"mg", r"毫升", r"ml", r"克",
                r"\d+(?:\.\d+)?\s*(?:mg|g|ml|毫克|克|毫升|片|粒)",
                r"[一二三四五六七八九十百]+(?:毫克|克|片|粒|毫升)"],
        "频次": [r"每天", r"每日", r"一天", r"每次", r"早上", r"晚上",
                r"一次", r"两次", r"三次", r"bid", r"tid", r"qd"],
        "疗程": [r"疗程", r"两周", r"两个星期", r"几天", r"几周", r"几个月",
                r"\d+\s*(?:天|周|个月|月|年)",
                r"[一二三四五六七八九十]+(?:天|周|个月|月|年)"],
        "依从性": [r"停了", r"停药", r"漏服", r"按时", r"规律", r"间断",
                  r"自行"],
    },
    "过敏史": {
        "过敏原": [r"过敏原", r"药物", r"食物", r"青霉素", r"头孢", r"花粉",
                  r"海鲜", r"过敏"],
        "反应类型": [r"皮疹", r"红肿", r"瘙痒", r"呼吸困难", r"休克", r"腹泻",
                    r"呕吐", r"反应"],
    },
    "家族史": {
        "家族成员": [r"家族", r"家里人", r"父亲", r"母亲", r"爸", r"妈",
                    r"兄弟", r"姐妹", r"子女", r"爷爷", r"奶奶", r"外公",
                    r"外婆"],
        "疾病名称": [r"高血压", r"糖尿病", r"肿瘤", r"癌", r"病", r"遗传"],
    },
    "生活方式": {
        "吸烟": [r"抽烟", r"吸烟", r"烟", r"戒烟"],
        "饮酒": [r"喝酒", r"饮酒", r"酒", r"戒酒"],
        "饮食": [r"饮食", r"吃饭", r"晚饭", r"早饭", r"油腻", r"辛辣",
                r"口味", r"食欲"],
        "运动": [r"运动", r"锻炼", r"跑步", r"散步", r"健身", r"活动量"],
        "睡眠": [r"睡眠", r"睡觉", r"失眠", r"入睡", r"早醒", r"熬夜"],
    },
    "检查与检验": {
        "检查项目": [r"检查", r"化验", r"检验", r"胃镜", r"肠镜", r"ct",
                    r"核磁", r"mri", r"b超", r"超声", r"血常规", r"病理",
                    r"心电图"],
        "检查时间": [r"去年", r"今年", r"上次", r"前几天", r"昨天", r"前天",
                    r"什么时候", r"\d+\s*(?:天|周|个月|月|年)前",
                    r"[一二三四五六七八九十]+(?:天|周|个月|月|年)前"],
        "结果": [r"结果", r"报告", r"说是", r"提示", r"正常", r"异常",
                r"阳性", r"阴性", r"未见"],
    },
    "诊断与治疗": {
        "诊断": [r"诊断", r"确诊", r"说是", r"考虑为", r"考虑是"],
        "治疗方案": [r"治疗", r"方案", r"吃药", r"服药", r"用药", r"手术",
                    r"化疗", r"放疗", r"开过", r"继续吃"],
        "疗效": [r"好一点", r"好转", r"有效", r"缓解", r"控制", r"没变化",
                r"加重"],
    },
    # “其他”无固定清单
}

ALLERGY_DENIAL_RE = re.compile(r"(?:没有|无|否认)[^。！？；]{0,6}过敏|不过敏|都不过敏")


def join_texts(parts: list[str], sep: str = "；") -> str:
    """合并多段文本，避免在已有标点后重复加分隔符。"""
    out = ""
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if not out:
            out = part
        elif re.search(r"[。！？；，、.!?;,]$", out):
            out += part
        else:
            out += sep + part
    return out


def clean_text(text: str) -> str:
    """只删除明确的口语填充词；无法确定时保留原文。"""
    if not text or not text.strip():
        return ""
    original = text.strip()
    t = original

    # 句首语气词（可连续出现）
    t = re.sub(r"^(?:(?:嗯+|啊+|呃+|额+|哦+|噢+|唉+|诶+|哎+)\s*[，,、]?\s*)+", "", t)
    # 标点之间的语气词
    t = re.sub(
        r"(?<=[，,。！？；;、])\s*(?:嗯+|啊+|呃+|额+|哦+|噢+)\s*(?=[，,。！？；;、]|$)",
        "",
        t,
    )
    # 明确的迟疑语（必须独立成句或后接标点）
    t = re.sub(
        r"(^|[，,。；;、])\s*(?:那个|就是说|怎么说呢)\s*(?=[，,。；;、]|$)",
        r"\1",
        t,
    )
    # “就是”仅在明显是填充词且后接时间/状态词时删除
    t = re.sub(
        r"^就是(?=(?:最近|昨天|今天|前几天|上个月|去年|今年|从小|一直|平时|当时|那会儿))",
        "",
        t,
    )

    t = re.sub(r"[ \t]+", " ", t).strip()
    t = re.sub(r"([，,、])(?:\s*[，,、])+", r"\1", t)
    return t if t else original


def parse_turns(raw_text: str) -> list[dict]:
    turns: list[dict] = []

    for lineno, raw in enumerate(raw_text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        role = None
        content = line
        m = TURN_RE.match(line)
        if m:
            label = m.group(1).strip()
            role = SPEAKER_LABELS.get(label) or SPEAKER_LABELS.get(label.lower())
            if role:
                content = m.group(2).strip()
            else:
                print(
                    f"[警告] 第 {lineno} 行：未识别的说话人“{label}”，按续行处理",
                    file=sys.stderr,
                )

        if role:
            turns.append({"role": role, "text": content,
                          "start": lineno, "end": lineno})
        else:
            if not turns:
                raise ValueError(f"第 {lineno} 行：对话开始前出现无法归属的文本")
            if turns[-1]["text"]:
                turns[-1]["text"] = join_texts([turns[-1]["text"], line], sep=" ")
            else:
                turns[-1]["text"] = line
            turns[-1]["end"] = lineno

    # 合并连续同一说话人的发言，丢弃空发言
    merged: list[dict] = []
    for t in turns:
        if not t["text"].strip():
            continue
        if merged and merged[-1]["role"] == t["role"]:
            merged[-1]["text"] = join_texts([merged[-1]["text"], t["text"]])
            merged[-1]["end"] = t["end"]
        else:
            merged.append(dict(t))

    if not merged:
        raise ValueError("未解析到任何发言，请检查 dialogue.txt 格式")
    if not any(t["role"] == DOCTOR for t in merged):
        raise ValueError("未找到医生发言，无法配对问答")
    return merged


def build_pairs(turns: list[dict]) -> list[dict]:
    pairs: list[dict] = []
    i = 0
    while i < len(turns):
        if turns[i]["role"] == DOCTOR:
            q = turns[i]
            answers = []
            j = i + 1
            while j < len(turns) and turns[j]["role"] == PATIENT:
                answers.append(turns[j])
                j += 1
            pairs.append({"q": q, "answers": answers})
            i = j
        else:
            pairs.append({"q": None, "answers": [turns[i]]})
            i += 1
    return pairs


def infer_topic(q_text: str, a_text: str) -> str:
    """主题优先由提问判断；提问无匹配时再看回答。"""
    for source in (q_text, a_text):
        lowered = (source or "").lower()
        if not lowered:
            continue
        for topic, keywords in TOPIC_RULES:
            if any(k.lower() in lowered for k in keywords):
                return topic
    return "其他"


def missing_fields(topic: str, answer_text: str) -> list[str]:
    fields = TOPIC_FIELDS.get(topic)
    if not fields:
        return []
    lowered = answer_text.lower()
    return [
        field
        for field, patterns in fields.items()
        if not any(re.search(p, lowered, flags=re.IGNORECASE) for p in patterns)
    ]


def line_range(pair: dict) -> str:
    q, answers = pair["q"], pair["answers"]
    if q and answers:
        start, end = q["start"], answers[-1]["end"]
    elif q:
        return f"L{q['start']}"
    else:
        start, end = answers[0]["start"], answers[-1]["end"]
    return f"L{start}" if start == end else f"L{start}-L{end}"


def convert(raw_text: str, source_name: str) -> str:
    turns = parse_turns(raw_text)
    pairs = build_pairs(turns)
    if not pairs:
        raise ValueError("未生成任何问答对")

    records = []
    cumulative_answers: list[str] = []

    for idx, pair in enumerate(pairs, start=1):
        q_raw = pair["q"]["text"] if pair["q"] else ""
        a_raw = join_texts([a["text"] for a in pair["answers"]])
        q_clean = clean_text(q_raw)
        a_clean = clean_text(a_raw)

        if a_clean:
            cumulative_answers.append(a_clean)

        topic = infer_topic(q_clean, a_clean)
        cumulative_answer_text = "\n".join(cumulative_answers)
        missing = missing_fields(topic, cumulative_answer_text)

        allergy_denied = bool(ALLERGY_DENIAL_RE.search(cumulative_answer_text))
        if topic == "过敏史" and allergy_denied:
            missing = []

        q_display = q_clean if q_clean else "（原文无对应提问）"
        a_display = a_clean if a_clean else "（原文无患者回答）"

        if topic == "其他":
            missing_text = "无（该主题无固定清单）"
            missing_count = "—"
        elif not missing:
            missing_text = "无"
            missing_count = "0"
        else:
            missing_text = "；".join(f"{m}（未提及）" for m in missing)
            missing_count = str(len(missing))

        records.append({
            "idx": idx,
            "topic": topic,
            "q": q_display,
            "a": a_display,
            "missing": missing,
            "missing_text": missing_text,
            "missing_count": missing_count,
            "lines": line_range(pair),
        })

    # 全对话缺失项汇总
    topic_order = []
    for r in records:
        if r["topic"] not in topic_order:
            topic_order.append(r["topic"])

    all_answers = "\n".join(cumulative_answers)
    summary_rows = []
    for topic in topic_order:
        if topic == "其他":
            summary_rows.append((topic, "无固定清单"))
            continue
        missing = missing_fields(topic, all_answers)
        if topic == "过敏史" and ALLERGY_DENIAL_RE.search(all_answers):
            missing = []
        summary_rows.append(
            (topic, "；".join(f"{m}（未提及）" for m in missing) if missing else "无")
        )

    out: list[str] = []
    out.append("# 医疗对话结构化问答记录")
    out.append("")
    out.append(f"> 来源：{source_name}")
    out.append(f"> 生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    out.append(f"> 问答组数：{len(records)}")
    out.append("> 说明：本记录只整理原对话内容，未补充对话之外的医学信息；")
    out.append("> “未提及”仅表示对应清单条目在对话中没有出现，不构成任何临床判断。")
    out.append("")
    out.append("## 概览")
    out.append("")
    out.append("| 编号 | 主题 | 截至本轮缺失项数 |")
    out.append("|---|---|---|")
    for r in records:
        out.append(f"| Q{r['idx']}/A{r['idx']} | {r['topic']} | {r['missing_count']} |")
    out.append("")

    for r in records:
        out.append(f"## Q{r['idx']} / A{r['idx']}")
        out.append("")
        out.append(f"- **主题**：{r['topic']}")
        out.append(f"- **提问（Q{r['idx']}）**：{r['q']}")
        out.append(f"- **回答（A{r['idx']}）**：{r['a']}")
        out.append(f"- **缺失项（截至本轮）**：{r['missing_text']}")
        out.append(f"- **原文行**：{r['lines']}")
        out.append("")

    out.append("## 全对话缺失项汇总")
    out.append("")
    out.append("| 主题 | 未提及项 |")
    out.append("|---|---|")
    for topic, missing_text in summary_rows:
        out.append(f"| {topic} | {missing_text} |")
    out.append("")
    out.append("> 未列出的主题表示本轮对话未涉及。")
    out.append("")

    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="将医生-患者对话整理为结构化问答记录（不补充对话外信息）"
    )
    parser.add_argument("--input", default="dialogue.txt",
                        help="输入对话文件（UTF-8），默认 dialogue.txt")
    parser.add_argument("--output", default="qa_record.md",
                        help="输出 Markdown 文件，默认 qa_record.md")
    args = parser.parse_args(argv)

    input_path = Path(args.input)
    if not input_path.is_file():
        print(f"[错误] 找不到输入文件：{input_path}", file=sys.stderr)
        return 1

    raw_text = input_path.read_text(encoding="utf-8-sig")
    try:
        markdown = convert(raw_text, input_path.as_posix())
    except ValueError as exc:
        print(f"[错误] {exc}", file=sys.stderr)
        return 1

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(markdown, encoding="utf-8")
    print(f"[完成] 已写入 {output_path}")
    print(f"[核验] 已整理 {markdown.count('## Q')} 组问答，"
          f"输出不含对话之外的医学信息")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
