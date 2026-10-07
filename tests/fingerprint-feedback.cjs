const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../dots/.config/quickshell/ii/modules/common/functions/FingerprintFeedback.js'), 'utf8');
const feedback = {};
vm.runInNewContext(source.replace(/^\.pragma library\s*/, ''), feedback);
for (const text of ['Failed to match fingerprint', '指纹匹配失败', '指紋不匹配'])
    assert.equal(feedback.fromPamMessage(text, true), 'mismatch');
for (const text of ['Verification timed out', '验证超时', '驗證逾時'])
    assert.equal(feedback.fromPamMessage(text, true), 'timeout');
// pam_fprintd retry prompts in English and its installed zh_CN / zh_TW translations.
for (const text of ['Place your finger on the reader again', 'Swipe was too short, try again',
    'Remove your finger, and try swiping your finger again', '请再次把您的手指放在阅读器上',
    '移开您的手指，并重新试着摁下', '摁的时间太短，请再试', '您的手指没有放正，请再摁一次',
    '抹動長度過短，請重試', '再次抹過您的手指'])
    assert.equal(feedback.fromPamMessage(text, true), 'retry', text);
assert.equal(feedback.fromPamMessage('Place your right index finger on the fingerprint reader', false), '');
assert.equal(feedback.fromPamMessage('请把您的右手食指放在指纹读取器上', false), '');
assert.equal(feedback.fromPamMessage('An unknown error occurred', true), 'unavailable');
assert.equal(feedback.message('mismatch'), '指纹未匹配，请重试');
assert.equal(feedback.message('timeout'), '指纹验证超时，请重试');
assert.equal(feedback.message('unavailable'), '指纹暂不可用，请输入密码');
assert.equal(feedback.message('exhausted'), '指纹尝试次数过多，请输入密码');
assert.equal(feedback.message('unexpected'), '');
for (const code of ['mismatch', 'unavailable', 'exhausted']) assert.equal(feedback.isError(code), true, code);
for (const code of ['retry', 'timeout', '']) assert.equal(feedback.isError(code), false, code);
console.log('Fingerprint feedback: mismatch, timeout, retry, unavailable and exhausted remain distinct.');
