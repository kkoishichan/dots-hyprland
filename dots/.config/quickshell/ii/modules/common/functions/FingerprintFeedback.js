.pragma library

function message(code) {
    switch (code) {
    case "mismatch": return "指纹未匹配，请重试";
    case "retry": return "请重新放置手指";
    case "timeout": return "指纹验证超时，请重试";
    case "unavailable": return "指纹暂不可用，请输入密码";
    case "exhausted": return "指纹尝试次数过多，请输入密码";
    default: return "";
    }
}

function isError(code) {
    return code === "mismatch" || code === "unavailable" || code === "exhausted";
}

function fromPamMessage(text, error) {
    const value = String(text || "").toLowerCase();
    if (/failed to match fingerprint|指纹匹配失败|指紋不匹配/.test(value)) return "mismatch";
    if (/verification timed out|验证超时|驗證逾時/.test(value)) return "timeout";
    // pam_fprintd retry prompts, including its zh_CN and zh_TW translations.
    if (/try again|finger again|reader again|重试|重試|再次|再试|再試|重新|再摁/.test(value)) return "retry";
    return error ? "unavailable" : "";
}
