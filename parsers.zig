const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const assertError = debug.assertError;
const warn = debug.warn;

fn toLower(ch: u8) u8 {
    return if ((ch >= 'A') and (ch <= 'Z')) ch + ('a' - 'A') else ch;
}

pub fn U8Iter() type {
    return struct {
        const Self = this;

        initial_idx: usize,
        idx: usize,
        str: [] const u8,

        pub fn init(str: [] const u8, initial_idx: usize) Self {
            return Self {
                .initial_idx = initial_idx,
                .idx = initial_idx,
                .str = str,
            };
        }

        pub fn set(pSelf: *Self, str: [] const u8, initial_idx: usize) void {
            pSelf.initial_idx = initial_idx;
            pSelf.idx = initial_idx;
            pSelf.str = str;
        }

        pub fn done(pSelf: *Self) bool {
            return pSelf.idx >= pSelf.str.len;
        }

        pub fn next(pSelf: *Self) void {
            if (!pSelf.done()) pSelf.idx += 1;
            warn ("I: next {}\n", pSelf);
        }

        pub fn curIdx(pSelf: *Self) usize {
            return pSelf.idx;
        }

        pub fn curCh(pSelf: *Self) u8 {
            if (pSelf.done()) return 0;
            return pSelf.str[pSelf.idx];
        }

        pub fn curChLc(pSelf: *Self) u8 {
            return toLower(pSelf.curCh());
        }

        // Peek next character, if end of string
        pub fn peekNextCh(pSelf: *Self) u8 {
            if (pSelf.done()) return 0;
            return pSelf.curCh();
        }

        // Peek Prev character or first character or 0 if end of string
        pub fn peekPrevCh(pSelf: *Self) u8 {
            var idx = if (pSelf.idx > pSelf.initial_idx) pSelf.idx - 1 else pSelf.idx;
            if (pSelf.done()) return 0;
            return pSelf.str[pSelf.idx];
        }

        // Next character or 0 if end of string
        pub fn nextCh(pSelf: *Self) u8 {
            if (pSelf.done()) return 0;
            var ch = pSelf.str[pSelf.idx];
            pSelf.idx += 1;
            return ch;
        }

        // Prev character or first character or if string is empty 0
        pub fn prevCh(pSelf: *Self) u8 {
            if (pSelf.idx > pSelf.initial_idx) pSelf.idx -= 1;
            return pSelf.peekNextCh();
        }

        // Next character skipping white space characters or 0 if end of string
        // Ignore ' ':0x20, HT:0x9
        // What about LF:0xA, VT:0xB, FF:0xC, CR:0xD, NEL:0x85, NBS:0xA0?
        // Or other White Space chars: https://en.wikipedia.org/wiki/Whitespace_character
        pub fn skipWs(pSelf: *Self) u8 {
            var ch = pSelf.curCh();
            while ((ch == ' ') or (ch == '\t')) {
                pSelf.next();
                ch = pSelf.curCh();
            }
            warn("SkipWs:- ch='{c}':0x{x} {}\n", ch, ch, pSelf);
            return ch;
        }

        // Next character converted to lower case or 0 if end of string
        pub fn nextChLc(pSelf: *Self) u8 {
            return toLower(pSelf.nextCh());
        }

        // Prev character converted to lower case or 0 the string is empty
        pub fn prevChLc(pSelf: *Self) u8 {
            return toLower(pSelf.prevCh());
        }

        // Next character converted to lower case skipping leading white space character
        pub fn nextChLcSkipWs(pSelf: *Self) u8 {
            return toLower(pSelf.skipWs());
        }
    };
}

pub fn ParseResult(comptime T: type) type {
    return struct {
        const Self = this;

        last_idx: usize,
        value: T,
        value_set: bool,
        digits: usize,

        pub fn init() Self {
            //warn("PR: init\n");
            return Self {
                .last_idx = 0,
                .value = 0,
                .value_set = false,
                .digits = 0,
            };
        }

        pub fn reinit(pSelf: *Self) void {
            //warn("PR: reinit\n");
            pSelf.last_idx = 0;
            pSelf.value = 0;
            pSelf.value_set = false;
            pSelf.digits = 0;
        }

        pub fn set(pSelf: *Self, v: T, last_idx: usize, digits: usize) void {
            //warn("PR: set v={} last_idx={}\n", v, last_idx);
            pSelf.last_idx = last_idx;
            pSelf.value = v;
            pSelf.value_set = true;
            pSelf.digits = digits;
        }
    };
}

// Return last charter with 0 if end of string
pub fn parseNumber(comptime T: type, pIter: *U8Iter(), radix_val: usize) ParseResult(T) {
    var result = ParseResult(T).init();
    pIter.initial_idx = pIter.idx;
    //var ch = pIter.curChLc();
    var ch = pIter.nextChLc();

    warn("PN:+  pr={}, it={} ch='{c}':0x{x}\n", result, pIter, ch, ch);
    defer warn("PN:-  pr={} it={} ch='{c}':0x{x}\n", result, pIter, ch, ch);

    var radix = radix_val;
    var value: u128 = 0;
    var negative: i128 = 1;

    // Handle leading +, -
    if (ch == '-') {
        ch = pIter.nextChLc();
        warn("PN: neg ch='{c}':0x{x}\n", ch, ch);
        negative = -1;
    } else if (ch == '+') {
        ch = pIter.nextChLc();
        warn("PN: plus ch='{c}':0x{x}\n", ch, ch);
        negative = 1;
    }

    // Handle radix if not passed
    if (radix == 0) {
        if ((ch == '0') and !pIter.done()) {
            switch (pIter.nextChLc()) {
                'b' => { radix = 2; ch = pIter.nextChLc(); },
                'o' => { radix = 8; ch = pIter.nextChLc(); },
                'd' => { radix = 10; ch = pIter.nextChLc(); },
                'x' => { radix = 16; ch = pIter.nextChLc(); },
                else => { radix = 10; ch = pIter.prevChLc(); },
            }
            warn("PN: radix={} ch='{c}':0x{x}\n", radix, ch, ch);
        } else {
            radix = 10;
            warn("PN: default radix={} ch='{c}':0x{x}\n", radix, ch, ch);
        }
    }

    // Handle remaining digits until end of string or an invalid character
    var digits: usize = 0;
    while (ch != 0) : (ch = pIter.nextChLc()) {
        warn("PN: TOL value={} it={} digits={} ch='{c}':0x{x}\n", value, pIter, digits, ch, ch);
        if (ch == '_') {
            continue;
        }

        var v: u8 = undefined;
        if ((ch >= '0') and (ch <= '9')) {
            v = ch - '0';
        } else if ((ch >= 'a') and (ch <= 'f')) {
            v = 10 + (ch - 'a');
        } else {
            // An invalid character, done
            warn("PN: bad ch='{c}':0x{x}\n", ch, ch);
            _ = pIter.prevCh();
            break;
        }
        // An invalid character for current radix, done
        if (v >= radix) {
            warn("PN: v:{} >= radix:{} ch='{c}':0x{x}\n", v, radix, ch, ch);
            _ = pIter.prevCh();
            break;
        }

        value *= radix;
        value += v;
        digits += 1;
    }
    warn("PN: AL value={} it={} digits={}\n", value, pIter, digits);

    // We didn't have any digits don't update result
    if (digits > 0) {
        if (negative < 0) {
            value = @bitCast(u128, negative *% @intCast(i128, value));
        }

        if (T.is_signed) {
            result.set(@intCast(T, @intCast(i128, value) & @intCast(T, -1)), pIter.curIdx(), digits);
        } else {
            result.set(@intCast(T, value & @maxValue(T)), pIter.curIdx(), digits);
        }
    }
    return result;
}

pub fn parseIntegerNumber(comptime T: type, pIter: *U8Iter()) !T {
    var result = ParseResult(T).init();
    var ch = pIter.skipWs();

    warn("PIN:+ pr={} it={} ch='{c}':0x{x}\n", result, pIter, ch, ch);
    defer warn("PIN:- pr={} it={} ch='{c}':0x{x}\n", result, pIter, ch, ch);

    result = parseNumber(T, pIter, 0);

    if (!result.value_set) {
        return error.NoValue;
    }

    return result.value;
}

pub fn parseInteger(comptime T: type, str: []const u8) !T {
    var result: T = undefined;
    var it: U8Iter() = undefined;

    it.set(str, 0);

    warn("PI:+ str={}\n", str);
    defer warn("PI:- result={} str={}\n", result, str);

    result = try parseIntegerNumber(T, &it);

    // Skip any trailing WS and if we didn't conusme the entire string it's an error
    _ = it.skipWs();
    if (it.idx < str.len) return error.NoValue;

    return result;
}

pub fn parseFloatNumber(comptime T: type, pIter: *U8Iter()) !T {
    var ch = pIter.skipWs();
    var pr = ParseResult(T).init();

    warn("PFN:+ pr={} it={} ch='{c}':0x{x}\n", pr, pIter, ch, ch);
    defer warn("PFN:- pr={} it={} ch='{c}':0x{x}\n", pr, pIter, ch, ch);

    // Get Tens
    var pr_tens = parseNumber(i128, pIter, 10);
    if (pr_tens.value_set) {
        warn("PFN: pr_tens={} it={} ch='{c}':0x{x}\n", pr_tens, pIter, pIter.curCh(), pIter.curCh());
        var pr_fraction = ParseResult(i128).init();
        var pr_exponent = ParseResult(i128).init();
        if (pIter.curCh() == '.') {
            // Get fraction
            pIter.next();
            pr_fraction = parseNumber(i128, pIter, 10);
            if (!pr_fraction.value_set) {
                warn("PF: no fraction\n");
                pr_fraction.set(0, pIter.idx, 0);
            }
        }
        warn("PFN: pr_fraction={} it={} ch='{c}':0x{x}\n", pr_fraction, pIter, pIter.curCh(), pIter.curCh());
        if (pIter.curCh() == 'e') {
            // Get Exponent
            pIter.next(); // skip e
            pr_exponent = parseNumber(i128, pIter, 10);
            if (!pr_exponent.value_set) {
                warn("PF: no exponent\n");
                pr_exponent.set(0, pIter.idx, 0);
            }
        }
        warn("PFN: pr_exponent={} it={} ch='{c}':0x{x}\n", pr_exponent, pIter, pIter.curCh(), pIter.curCh());

        var tens = @intToFloat(T, pr_tens.value);
        var fraction = @intToFloat(T, pr_fraction.value) / std.math.pow(T, 10, @intToFloat(T, pr_fraction.digits));
        var significand: T = if (pr_tens.value >= 0) tens + fraction else tens - fraction;
        var value = significand * std.math.pow(T, @intToFloat(T, 10), @intToFloat(T, pr_exponent.value));
        pr.set(value, pIter.idx, pr_tens.digits + pr_fraction.digits);

        warn("PFN:-- pr.value={}\n", pr.value);
        return pr.value;
    }
    return error.NoValue;
}

pub fn parseFloating(comptime T: type, str: []const u8) !T {
    var it: U8Iter() = undefined;
    it.set(str, 0);

    var result = try parseFloatNumber(T, &it);
    warn("PF:- result={} str={}\n", result, str);
    return result;
}

test "parseIntegerNumber" {
    warn("\n");
    var ch: u8 = undefined;
    var it: U8Iter() = undefined;

    it.set("", 0);
    assertError(parseIntegerNumber(u8, &it), error.NoValue);

    it.set("0", 0);
    var vU8 = try parseIntegerNumber(u8, &it);
    assert(vU8 == 0);
    assert(it.idx == 1);

    it.set("1 2", 0);
    vU8 = try parseIntegerNumber(u8, &it);
    warn("vU8={} it={}\n", vU8, it);
    assert(vU8 == 1);
    assert(it.idx == 1);
    vU8 = try parseIntegerNumber(u8, &it);
    warn("vU8={} it={}\n", vU8, it);
    assert(vU8 == 2);
    assert(it.idx == 3);

    it.set("\t0", 0);
    vU8 = try parseIntegerNumber(u8, &it);
    assert(vU8 == 0);
    assert(it.idx == 2);

    it.set(" \t0", 0);
    vU8 = try parseIntegerNumber(u8, &it);
    assert(vU8 == 0);
    assert(it.idx == 3);

    it.set(" \t 0", 0);
    vU8 = try parseIntegerNumber(u8, &it);
    assert(vU8 == 0);
    assert(it.idx == 4);

    it.set("1.", 0);
    vU8 = try parseIntegerNumber(u8, &it);
    assert(vU8 == 1);
    assert(it.idx == 1);
}

test "parseInteger" {
    assertError(parseInteger(u8, ""), error.NoValue);

    assert((try parseInteger(u8, "0")) == 0);
    assert((try parseInteger(u8, " 1")) == 1);
    assert((try parseInteger(u8, " 2 ")) == 2);
    assertError(parseInteger(u8, " 2d"), error.NoValue);

    const s = " \t 123\t";
    var slice = s[0..];
    assert((try parseInteger(u8, slice)) == 123);

    assert((try parseInteger(i8, "-1")) == -1);
    assert((try parseInteger(i8, "1")) == 1);
    assert((try parseInteger(i8, "+1")) == 1);

    assert((try parseInteger(u8, "0b0")) == 0);
    assert((try parseInteger(u8, "0b1")) == 1);
    assert((try parseInteger(u8, "0b1010_0101")) == 0xA5);
    assertError(parseInteger(u8, "0b2"), error.NoValue);

    assert((try parseInteger(u8, "0o0")) == 0);
    assert((try parseInteger(u8, "0o1")) == 1);
    assert((try parseInteger(u8, "0o7")) == 7);
    assert((try parseInteger(u8, "0o77")) == 0x3f);
    assert((try parseInteger(u32, "0o111_777")) == 0b1001001111111111);
    assertError(parseInteger(u8, "0b8"), error.NoValue);

    assert((try parseInteger(u8, "0d0")) == 0);
    assert((try parseInteger(u8, "0d1")) == 1);
    assert((try parseInteger(u8, "-0d1")) == 255);
    assert((try parseInteger(i8, "-0d1")) == -1);
    assert((try parseInteger(i8, "+0d1")) == 1);
    assert((try parseInteger(u8, "0d9")) == 9);
    assert((try parseInteger(u8, "0")) == 0);
    assert((try parseInteger(u8, "-1")) == 255);
    assert((try parseInteger(u8, "9")) == 9);
    assert((try parseInteger(u8, "127")) == 0x7F);
    assert((try parseInteger(u8, "-127")) == 0x81);
    assert((try parseInteger(u8, "-128")) == 0x80);
    assert((try parseInteger(u8, "255")) == 255);
    assert((try parseInteger(u8, "256")) == 0);
    assert((try parseInteger(u64, "123_456_789")) == 123456789);

    assert((try parseInteger(u8, "0x0")) == 0x0);
    assert((try parseInteger(u8, "0x1")) == 0x1);
    assert((try parseInteger(u8, "0x9")) == 0x9);
    assert((try parseInteger(u8, "0xa")) == 0xa);
    assert((try parseInteger(u8, "0xf")) == 0xf);

    assert((try parseInteger(i128, "-170141183460469231731687303715884105728")) == @bitCast(i128, @intCast(u128, 0x80000000000000000000000000000000)));
    assert((try parseInteger(i128, "-170141183460469231731687303715884105727")) == @bitCast(i128, @intCast(u128, 0x80000000000000000000000000000001)));
    assert((try parseInteger(i128, "-1")) == @bitCast(i128, @intCast(u128, 0xffffffffffffffffffffffffffffffff)));
    assert((try parseInteger(i128, "0"))  == @bitCast(i128, @intCast(u128, 0x00000000000000000000000000000000)));
    assert((try parseInteger(i128, "170141183460469231731687303715884105726")) == @bitCast(i128, @intCast(u128, 0x7ffffffffffffffffffffffffffffffe)));
    assert((try parseInteger(i128, "170141183460469231731687303715884105727")) == @bitCast(i128, @intCast(u128, 0x7fffffffffffffffffffffffffffffff)));

    assert((try parseInteger(u128, "0"))  == 0);
    assert((try parseInteger(u128, "1"))  == 1);
    assert((try parseInteger(u128, "340282366920938463463374607431768211454")) == 0xfffffffffffffffffffffffffffffffe);
    assert((try parseInteger(u128, "340282366920938463463374607431768211455")) == 0xffffffffffffffffffffffffffffffff);

    assert((try parseInteger(u128, "0x1234_5678_9ABc_Def0_0FEd_Cba9_8765_4321")) == 0x123456789ABcDef00FEdCba987654321);
    assertError(parseInteger(u8, "0xg"), error.NoValue);
}

pub fn floatFuzzyEql(comptime T: type, lhs: T, rhs: T, fuz: T) bool {
    // Determine which is larger and smallerj
    // then add the fuz to smaller and subract from larger
    // If smaller >= larger then they are equal
    var smaller: T = undefined;
    var larger: T  = undefined;
    if (lhs > rhs) {
        larger = lhs - fuz;
        smaller = rhs + fuz;
    } else {
        larger = rhs - fuz;
        smaller = lhs + fuz;
    }
    //warn("smaller={} larger={}\n", smaller, larger);
    return smaller >= larger;
}

test "parseFloatNumber" {
    warn("\n");
    var ch: u8 = undefined;
    var it: U8Iter() = undefined;
    var vF32: f32 = undefined;

    it.set("", 0);
    assertError(parseFloatNumber(f32, &it), error.NoValue);

    it.set("0", 0);
    vF32 = try parseFloatNumber(f32, &it);
    assert(vF32 == 0);
    assert(it.idx == 1);

    it.set("1", 0);
    vF32 = try parseFloatNumber(f32, &it);
    assert(vF32 == 1);
    assert(it.idx == 1);

    it.set("+1", 0);
    vF32 = try parseFloatNumber(f32, &it);
    assert(vF32 == 1);
    assert(it.idx == 2);

    it.set("-1", 0);
    vF32 = try parseFloatNumber(f32, &it);
    assert(vF32 == -1);
    assert(it.idx == 2);

    it.set("1.2", 0);
    vF32 = try parseFloatNumber(f32, &it);
    assert(vF32 == 1.2);
    assert(it.idx == 3);

    it.set("1e1", 0);
    vF32 = try parseFloatNumber(f32, &it);
    assert(vF32 == 10);
    assert(it.idx == 3);

    it.set("1.2 3.4", 0);
    vF32 = try parseFloatNumber(f32, &it);
    warn("vF32={} it={}\n", vF32, it);
    assert(vF32 == 1.2);
    assert(it.idx == 3);
    vF32 = try parseFloatNumber(f32, &it);
    warn("vF32={} it={}\n", vF32, it);
    assert(vF32 == 3.4);
    assert(it.idx == 7);
}

test "parseFloat" {
    assert((try parseFloating(f32, "0")) == 0);
    assert((try parseFloating(f32, "-1")) == -1);
    assert((try parseFloating(f32, "1.")) == 1.0);
    assert((try parseFloating(f32, "1e0")) == 1);
    assert((try parseFloating(f32, "1e1")) == 10);
    assert((try parseFloating(f32, "1e-1")) == 0.1);
    assert((try parseFloating(f32, "0.1")) == 0.1);
    assert((try parseFloating(f32, "-1.")) == -1.0);
    assert((try parseFloating(f32, "-2.1")) == -2.1);
    assert((try parseFloating(f32, "-1.2")) == -1.2);
    assert(floatFuzzyEql(f32, try parseFloating(f32,  "1.2e2"),    1.2e2 , 0.00001));
    assert(floatFuzzyEql(f32, try parseFloating(f32, "-1.2e-2"),  -1.2e-2, 0.00001));
}