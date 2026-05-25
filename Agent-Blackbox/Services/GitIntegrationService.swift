import Foundation
import Combine

struct GitCommitCost: Identifiable, Hashable {
    var id: String { hash }
    let hash: String
    let author: String
    let date: Date
    let message: String
    var totalTokens: Int
}

@MainActor
final class GitIntegrationService: ObservableObject {
    @Published var commitCosts: [GitCommitCost] = []
    @Published var isScanning = false
    
    private weak var database: DatabaseService?
    
    func bind(database: DatabaseService) {
        self.database = database
    }
    
    func scanCommits(repoPath: String) {
        guard let database = database else { return }
        self.isScanning = true
        
        Task.detached {
            let commits = await self.fetchGitCommits(repoPath: repoPath)
            var computedCosts: [GitCommitCost] = []
            
            // Loop through commits and aggregate cost between this commit and the previous one
            for i in 0..<commits.count {
                let currentCommit = commits[i]
                let sinceDate: Date
                
                if i + 1 < commits.count {
                    // Previous commit in chronological order (which is index i+1 since we fetch reverse-chronological)
                    sinceDate = commits[i+1].date
                } else {
                    // Fallback: 2 hours before the current commit
                    sinceDate = currentCommit.date.addingTimeInterval(-2 * 3600)
                }
                
                let untilDate = currentCommit.date
                
                // Aggregate usage between sinceDate and untilDate
                let usage = await database.aggregateUsage(provider: nil, since: sinceDate, until: untilDate)
                
                var costInfo = currentCommit
                costInfo.totalTokens = usage.totalTokens
                computedCosts.append(costInfo)
            }
            
            let finalCosts = computedCosts
            await MainActor.run {
                self.commitCosts = finalCosts
                self.isScanning = false
            }
        }
    }
    
    private func fetchGitCommits(repoPath: String) async -> [GitCommitCost] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        
        // Format: Hash | AuthorName | UnixTimestamp | Subject
        process.arguments = ["log", "-n", "10", "--pretty=format:%H|%an|%ct|%s"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                return []
            }
            
            var list: [GitCommitCost] = []
            let lines = output.components(separatedBy: .newlines)
            
            for line in lines {
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 4 else { continue }
                
                let hash = parts[0]
                let author = parts[1]
                guard let timestampSecs = Double(parts[2]) else { continue }
                let date = Date(timeIntervalSince1970: timestampSecs)
                let message = parts[3]
                
                list.append(GitCommitCost(
                    hash: hash,
                    author: author,
                    date: date,
                    message: message,
                    totalTokens: 0
                ))
            }
            return list
        } catch {
            Logger.shared.error("Failed to run git log: \(error.localizedDescription)")
            return []
        }
    }
}
