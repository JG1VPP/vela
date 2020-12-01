module gc;

import core.stdc.stdlib: exit, malloc, free;
import std.algorithm.mutation: remove;
import std.conv: emplace;

import std.stdio;

struct Head {
	bool marked;
	void *from;
	void *last;
};
Head*[] heads;
T alloc(T,Args...)(Args args) {
	return emplace!(T)(ralloc(__traits(classInstanceSize,T)), args);
}
void[] ralloc(size_t bytes) {
	Head* head = new Head;
	heads ~= head;
	void *p = malloc(bytes);
	size_t a1 = cast(size_t) p;
	size_t a2 = a1 + bytes;
	head.from = cast(void*) a1;
	head.last = cast(void*) a2;
	head.marked = false;
	return p[0..bytes];
}
static Head* owner(void *ptr) {
	foreach(head; heads) {
		void *from = head.from;
		void *last = head.last;
		if(ptr < from) continue;
		if(ptr > last) continue;
		return head;
	}
	return null;
}
static void mark(void *ptr) {
	Head* head = owner(ptr);
	if(head == null) return;
	if(head.marked) return;
	head.marked = true;
	void *from = head.from;
	void *last = head.last;
	size_t s = cast(size_t) from;
	size_t e = cast(size_t) last;
	for(size_t i=s; i<e; i++) {
		mark(* cast(void**) i);
	}
}
void clean() {
	foreach(head; heads) if(!head.marked) free(head.from);
	heads = heads.remove!("!a.marked");
	foreach(head; heads) head.marked = false;
}
