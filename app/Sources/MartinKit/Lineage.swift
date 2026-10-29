import Darwin

struct Lineage {
    struct Member: Hashable {
        let pid: pid_t
        let started: UInt64
    }

    private struct Entry {
        let member: Member
        let parent: pid_t
        let group: pid_t
    }

    let group: pid_t
    private let pipes: Set<UInt64>
    private(set) var members: Set<Member> = []

    init(leader: pid_t, pipes descriptors: [Int32]) {
        group = leader
        pipes = Set(descriptors.flatMap { descriptor -> [UInt64] in
            var info = pipe_fdinfo()
            guard proc_pidfdinfo(getpid(), descriptor, PROC_PIDFDPIPEINFO, &info, Int32(MemoryLayout<pipe_fdinfo>.size)) > 0 else { return [] }
            return [info.pipeinfo.pipe_handle, info.pipeinfo.pipe_peerhandle]
        })
        if let leader = Self.entry(of: leader) { members.insert(leader.member) }
    }

    mutating func record(holders: Bool = false) {
        let table = Self.table()
        var known = Set(members.map(\.pid))
        var grown = true
        while grown {
            let found = table.filter { !known.contains($0.member.pid) && (known.contains($0.parent) || $0.group == group || holders && holds($0.member.pid)) }
            found.forEach { members.insert($0.member) }
            known.formUnion(found.map(\.member.pid))
            grown = !found.isEmpty
        }
    }

    func escaped() -> [Member] {
        members.filter { Self.entry(of: $0.pid)?.group != group }
    }

    static func kill(_ members: some Sequence<Member>) {
        for member in members where entry(of: member.pid)?.member == member {
            Darwin.kill(member.pid, SIGKILL)
        }
    }

    private func holds(_ pid: pid_t) -> Bool {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return false }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let filled = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)) / MemoryLayout<proc_fdinfo>.size
        return descriptors.prefix(filled).contains { descriptor in
            var info = pipe_fdinfo()
            return descriptor.proc_fdtype == PROX_FDTYPE_PIPE
                && proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDPIPEINFO, &info, Int32(MemoryLayout<pipe_fdinfo>.size)) > 0
                && pipes.contains(info.pipeinfo.pipe_handle)
        }
    }

    private static func table() -> [Entry] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let user = getuid(), me = getpid()
        return pids.prefix(max(count, 0)).filter { $0 != me }.compactMap { entry(of: $0, owner: user) }
    }

    private static func entry(of pid: pid_t, owner: uid_t? = nil) -> Entry? {
        var info = proc_bsdinfo()
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              owner.map({ $0 == info.pbi_uid }) ?? true else { return nil }
        let started = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        return Entry(member: Member(pid: pid, started: started), parent: pid_t(info.pbi_ppid), group: pid_t(info.pbi_pgid))
    }
}
