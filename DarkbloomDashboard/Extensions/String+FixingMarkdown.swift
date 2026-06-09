import Foundation

extension String {
    
    /// Attempt to fix broken markdown.
    var fixingMarkdown: String {
        var openCodeBlock: Bool = false
        
        var lines = self.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, line) in lines.enumerated() {
            
            // Check for open code block
            if line.contains(/(?m)^\s*?`{3}\w+?$/) {
                openCodeBlock = true
            }
            
            // Check for open inline code block
            else if line.contains(/(?m)`(?!`{2})[^`]+?$/) {
                lines[offset].append("`")
            }
            
            // Check for closed code block
            if openCodeBlock && line.contains(/(?m)^\s*?`{3}$/) {
                openCodeBlock = false
            }
        }
        
        // Close code block
        if openCodeBlock {
            lines.append("```")
        }
        
        return lines.joined(separator: "\n")
    }
}
