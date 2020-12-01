/**
 * D言語でLISPを作る本 (vela.pdf)
 *
 * PEG
 * LISP
 * GC
 *
 * vela: evalのもじり&星座の帆座(vela)
 */

module vela;
import std.range;
import std.array;
import std.stdio;
import std.conv;
import std.format;
import std.algorithm;
import std.container;
import std.regex;
import std.typecons;
import std.variant;
import std.traits;
import gc;

string any(R,N)(ref R src, ref N node) {
	if(src.empty) return null;
	auto ch = src.front;
	src.popFront();
	return format!"%c"(ch);
}

string eof(R,N)(ref R src, ref N node) {
	return src.empty? "": null;
}

template cls(string P) {
	string cls(R,N)(ref R src, ref N node) {
		if(src.empty) return null;
		foreach(p; P) if(src.front == p) {
			src.popFront;
			return format!"%c"(p);
		}
		return null;
	}
}

template ch(alias C) {
	string ch(R,N)(ref R src, ref N node) {
		if(src.empty || src.front != C) return null;
		src.popFront;
		return format!"%c"(C);
	}
}

template rng(alias L, alias U) {
	string rng(R,N)(ref R src, ref N node) {
		if(src.empty) return null;
		if(src.front < L) return null;
		if(src.front > U) return null;
		auto ch = src.front;
		src.popFront;
		return format!"%c"(ch);
	}
}

template and(alias P) {
	string and(R,N)(ref R src, ref N node) {
		auto before = src.save;
		scope(exit) src = before;
		return P(src, node)? "": null;
	}
}

template not(alias P) {
	string not(R,N)(ref R src, ref N node) {
		auto before = src.save;
		scope(exit) src = before;
		return P(src, node)? null: "";
	}
}

template opt(alias P) {
	string opt(R,N)(ref R src, ref N node) {
		auto result = P(src, node);
		return result is null? "": result;
	}
}

template rep0(alias P) {
	string rep0(R,N)(ref R src, ref N node) {
		string result = "";
		while(true) {
			string ast = P(src, node);
			if(ast) result ~= ast;
			else break;
		}
		return result;
	}
}

template list(alias P) {
	string list(R,N)(ref R src, ref N node) {
		N child = alloc!N();
		string result = P(src, child);
		if(result) node ~= child;
		return result;
	}
}

template atom(alias P, alias C) {
	string atom(R,N)(ref R src, ref N node) {
		string result = P(src,node);
		if(result) node ~= C(result);
		return result;
	}
}

template rep1(alias P) {
	string rep1(R,N)(ref R src, ref N node) {
		string result = "";
		bool ok = false;
		while(true) {
			string ast = P(src, node);
			if(ast) {
				ok = true;
				result ~= ast;
			}
			else break;
		}
		return ok? result: null;
	}
}

template seq(P...) {
	string seq(R,N)(ref R src, ref N node) {
		auto before = src.save;
		scope(failure) src = before;
		string result = "";
		foreach(p; P) {
			string ast = p(src, node);
			if(!ast) {
				src = before;
				return null;
			} else result ~= ast;
		}
		return result;
	}
}

template or(P...) {
	string or(R,N)(ref R src, ref N node) {
		foreach(p; P) {
			string ast = p(src, node);
			if(ast) return ast;
		}
		return null;
	}
}

template Lazy(string src) {
	template Lazy() {
		mixin(format!"alias %s Lazy;"(src));
	}
}

interface Operator: Sexp {}

interface Sexp {
	bool opEquals(Object that);
	string toString();
	public Sexp opCall(Scope env);
	public final Long asLong() const {
		return cast(Long) this;
	}
	public final Lambda asLambda() const {
		return cast(Lambda) this;
	}
	public final Syntax asSyntax() const {
		return cast(Syntax) this;
	}
	public final Native asNative() const {
		return cast(Native) this;
	}
	public final Symbol asSymbol() const {
		return cast(Symbol) this;
	}
}

mixin template atom() {
	public Sexp opCall(Scope env) const {
		return cast(Sexp) this;
	}
	override hash_t toHash() const {
		return typeid(val).getHash(&val);
	}
}

bool isInstanceOf(T,R)(R sexp) {
	return (cast(T) sexp) !is null;
}

class Symbol: Sexp {
	private immutable string val;
	this(string val) {
		this.val = val;
	}
	override string toString() const {
		return val;
	}
	override bool opEquals(Object that) const {
		if(!that.isInstanceOf!Symbol) return false;
		return (cast(Symbol) that).val == this.val;
	}
	override hash_t toHash() const {
		return typeid(val).getHash(&val);
	}
	override Sexp opCall(Scope env) const {
		return env[this.asSymbol];
	}
}

class Long: Sexp {
	private immutable long val;
	this(long val) {
		this.val = val;
	}
	public long value() {
		return val;
	}
	override string toString() const {
		return to!string(val);
	}
	override bool opEquals(Object that) const {
		if(!that.isInstanceOf!Long) return false;
		return (cast(Long) that).val == this.val;
	}
	mixin atom;
}

class String: Sexp {
	private immutable string val;
	this(string val) {
		this.val = val;
	}
	override string toString() const {
		return format!"\"%s\""(val);
	}
	override bool opEquals(Object that) const {
		if(!that.isInstanceOf!String) return false;
		return (cast(String) that).val == this.val;
	}
	mixin atom;
}

public final class ListRange {
	private List head;
	private this(List head) {
		this.head = head;
	}
	@property Sexp front() {
		return cast(Sexp) head.car;
	}
	void popFront() {
		head = cast(List) head.cdr;
	}
	@property bool empty() {
		return head is null || head.car is null;
	}
}

class List: Sexp {
	public Sexp car;
	public List cdr;
	this(Sexp car, List cdr) {
		this.car = car;
		this.cdr = cdr;
	}
	this() {
		this.car = null;
		this.cdr = null;
	}
	this(Sexp car, Sexp[] cdr...) {
		this.car = car;
		if(cdr.length == 0) this.cdr = null;
		else this.cdr = alloc!List(cdr[0],cdr[1..$]);
	}
	public List opOpAssign(string op)(Sexp cdar) if(op == "~") {
		if(!empty()) {
			List tail = this;
			while(tail.cdr !is null) {
				tail = tail.cdr;
			}
			tail.cdr = alloc!List(cdar, null);
		} else {
			this.car = cdar;
		}
		return this;
	}
	public ListRange toRange() {
		return new ListRange(this);
	}
	public bool empty() {
		return car is null;
	}
	public ulong size() {
		return walkLength(this.toRange());
	}
	override bool opEquals(Object that) {
		if(!that.isInstanceOf!String) return false;
		return toRange().equal((cast(List) that).toRange());
	}
	override string toString() {
		return format!"(%s)"(map!(to!string)(toRange()).join(" "));
	}
	override public Sexp opCall(Scope env) {
		if(empty) return cast(Sexp) this;
		auto car = this.car(env);
		if(car.isInstanceOf!Lambda) return car.asLambda()(cdr, env);
		if(car.isInstanceOf!Native) return car.asNative()(cdr, env);
		throw new Exception("UNCALLABLE");
	}
}

public class Scope {
	public Sexp[Symbol] bind;
	public const Scope enclosure;
	public this() {
		this.enclosure = null;
	}
	public this(const Scope enclosure) {
		this.enclosure = enclosure;
	}
	public Sexp opIndex(Symbol key) {
		if(key in bind) return bind[key];
		if(enclosure !is null) return (cast(Scope) enclosure)[key];
		throw new Exception(format!"%s not declared"(key));
	}
	public Sexp opIndexAssign(Sexp val, Symbol key) {
		bind[key] = val;
		return val;
	}
	public Sexp opIndexAssign(Sexp val, string key) {
		return this[new Symbol(key)] = val;
	}
	public Sexp opIndexAssign(Sexp function (List, Scope) op, string key) {
		return this[key] = new class() Native {
			override public string toString() {
				return format!"#<system function %s>"(key);
			}
			public override Sexp opCall(List args, Scope eval) {
				return op(args, eval);
			}
		};
	}
}

public abstract class Native: Operator {
	public final override bool opEquals(Object that) {
		return this is that;
	}
	public final Sexp opCall(Scope eval) {
		return this;
	}
	public Sexp opCall(List args, Scope eval);
}

public final class Lambda: Operator {
	private List pars;
	private Sexp sexp;
	private Scope time;
	public this(List list, Scope time) {
		this.pars = cast(List) list.car;
		this.sexp = list.cdr.car;
		this.time = time;
	}
	public override string toString() const {
		return format!"(lambda %s %s)"(pars,sexp);
	}
	override public Sexp opCall(Scope env) const {
		return cast(Sexp) this;
	}
	public Sexp opCall(List args, Scope env) {
		auto child = alloc!Scope(time);
		if(args.size() == args.size()) {
			auto prng = (cast(List) pars).toRange();
			auto arng = (cast(List) args).toRange();
			foreach(e; zip(prng,arng)) child[e[0].asSymbol] = e[1](env);
			return sexp(child);
		}
		throw new Exception(format!"%s needs %d args"(this,pars.size()));
	}
	public override bool opEquals(Object that) const {
		if(!that.isInstanceOf!Lambda) return false;
		if((cast (Sexp) that).asLambda().pars != pars) return false;
		if((cast (Sexp) that).asLambda().sexp != sexp) return false;
		if((cast (Sexp) that).asLambda().time != time) return false;
		return true;
	}
}

public final class Syntax: Sexp {
	private List pars;
	private Sexp sexp;
	private Scope time;
	public this(List list, Scope time) {
		this.pars = cast(List) list.car;
		this.sexp = list.cdr.car;
		this.time = time;
	}
	public override string toString() const {
		return format!"(syntax %s %s)"(pars,sexp);
	}
	override public Sexp opCall(Scope env) const {
		return cast(Sexp) this;
	}
	public Sexp opCall(List args, Scope env) {
		auto child = alloc!Scope(time);
		if(pars.size() == args.size()) {
			auto prng = (cast(List) pars).toRange();
			auto arng = (cast(List) args).toRange();
			foreach(e; zip(prng,arng)) child[e[0].asSymbol] = e[1];
			return sexp(child)(env);
		}
		throw new Exception(format!"%s needs %d args"(this,pars.size()));
	}
	public override bool opEquals(Object that) const {
		if(!that.isInstanceOf!Syntax) return false;
		if((cast (Sexp) that).asSyntax().pars != pars) return false;
		if((cast (Sexp) that).asSyntax().sexp != sexp) return false;
		if((cast (Sexp) that).asSyntax().time != time) return false;
		return true;
	}
}

alias rep1!(cls!" \r\n") SPACE;
alias or!(SPACE, cls!"()'`,", eof) DELIM;
alias atom!(rep1!(seq!(not!DELIM, any)), sexp => alloc!Symbol(sexp)) SYMBOL;
alias atom!(seq!(rep1!(rng!('0','9')),and!DELIM), sexp => alloc!Long(to!int(sexp))) NUMBER;

alias seq!(and!(ch!'"'), any) DQUOT;
alias or!(seq!(ch!'\\', cls!"\\bnfrt\""), seq!(not!(cls!"\\\""), any)) CH1;
alias seq!(DQUOT, atom!(rep0!CH1, sexp => alloc!String(sexp)), DQUOT) STRING;

alias or!(NUMBER, STRING, QUOTE, SYMBOL, Lazy!q{LIST}) EXP1;
alias seq!(EXP1, rep0!(seq!(opt!SPACE, EXP1))) EXPN;

alias list!(seq!(atom!(cls!"'`,", sexp => alloc!Symbol(
	["'": "quote", "`": "quasi-quote", ",": "unquote"][sexp]
)), Lazy!q{EXP1})) QUOTE;

alias list!(seq!(ch!'(', opt!SPACE, opt!EXPN, opt!SPACE, ch!')')) LIST;

alias seq!(opt!SPACE, EXPN, opt!SPACE, eof) LINE;

Sexp add(List args, Scope eval) {
	return new Long(reduce!("a+b")(map!(arg => arg(eval).asLong.value)(args.toRange)));
}

private Scope createRootScope() {
	Scope root = new Scope();
	root["+"] = &add;
	return root;
}

void main(string[] args) {
	Scope root = createRootScope();
	while(true) {
		write("DLANG-PEG-LISP> ");
		auto text = readln().replace("\n","");
		List prog = alloc!List();
		auto result = LINE(text, prog);
		try {
			foreach(sexp; prog.toRange()) writeln(sexp(root));
			foreach(sexp; root.bind) mark(&sexp);
			clean();
		} catch (Exception ex) {
			writeln("ERROR(", typeid(ex), "): ", ex.msg);
		}
	}
}
