import ArgumentParser
import Cocoa


enum DownloadError: Error {
    case FileNotFound
    case BadURL
}

// Thread safe collection of images.  Probably overkill needed with so few
// images
actor ImageCollection {
    var images : [NSImage] = []
    
    func append(_ image : NSImage) {
        if image.size.width != 0.0 {
            images.append(image)
        }
    }
    
    var count : Int { images.count }
}

extension Date {
    static var currentTimeStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd H:mm:ss.SSSS"
        return (formatter.string(from: Date()) as NSString) as String
    }
}

/// Simple log actor for showing progress of multiple threads
/// Instantiate with number of columns and column width, then
/// include an index in the .log() call to indent by index * width spaces.
/// e.g.
/// 06-20 12:19:35.2010 Image 1     Image 2     Image 3     Image 4
/// 06-20 12:19:35.2010 ------------------------------------------------
/// 06-20 12:19:35.2010 REQUESTED
/// 06-20 12:19:35.2020             REQUESTED
/// 06-20 12:19:35.2020                         REQUESTED
/// 06-20 12:19:35.2020                                     REQUESTED
/// 06-20 12:19:36.2340                                     RECEIVED
/// 06-20 12:19:37.5400                         ERROR!!!!
/// 06-20 12:19:38.2110             RECEIVED
/// 06-20 12:19:40.2080 RECEIVED
/// 06-20 12:19:40.2090 ------------------------------------------------

actor ProgressLog {
    let columns : Int
    let width : Int
    
    func log(_ message: String, index:Int = 0) {
        let indent = String(repeating: " ", count: index * width)
        print("\(Date.currentTimeStamp) \(indent)\(message)")
    }
    
    init(columns: Int, width: Int) {
        self.columns = columns
        self.width = width
    }
}


/// Using swift-argument-parser to parse the trivial args
/// and set up an async context for our @main
@main
struct AsyncCLI1 : AsyncParsableCommand {
    @Argument(help: "Image URLs to retrieve")
    var imageURLStrings : [String] = [
        "https://f4.bcbits.com/img/a1974051391_16.jpg",
        "https://static.wikia.nocookie.net/southpark/images/c/c6/MrsBiggle.png/revision/latest?cb=20170122031537",
        "https://www.lego.com/cdn/cs/catalog/assets/DOES_NOT_EXIST.png",
        "https://static.wikia.nocookie.net/muppet/images/d/de/Palisadesgallery-beauregard.png/revision/latest/scale-to-width-down/280?cb=20160208000514",
    ]
    
    mutating func run() async throws {
        @Sendable func downloadImage(from url: URL) async throws -> NSImage? {
            let delay = Int.random(in: 1...5)
            Thread.sleep(forTimeInterval: TimeInterval(delay))  // delay for 1...5 seconds to make it more interesting

            let (data, _) = try await URLSession.shared.data(from: url)
            guard data.count != 0 else {
                throw DownloadError.FileNotFound
            }
            return NSImage(data: data)
        }
        
        // Start logging...
        let columnCount = imageURLStrings.count
        let columnWidth = 12
        let plog = ProgressLog(columns: columnCount, width: columnWidth)
        await plog.log("AsyncCLI1 Started")
        await plog.log("Retrieving \(imageURLStrings.count) images.")
        
        // List images to download
        for (i, imageURLString) in imageURLStrings.enumerated() {
            await plog.log("Image \(i+1):  \(imageURLString)")
        }
        
        // dump header for thread progress table
        await plog.log(" ")
        await plog.log(
            Array(1...columnCount).map {
                "Image \($0)".padding(toLength: columnWidth, withPad: " ", startingAt: 0)
            }.joined()
        )
        await plog.log(String(repeating: "-", count: columnCount * columnWidth))
        
        
        // Do the real work in a TaskGroup
        // Could replace with async let?
        let allResults : ImageCollection = try await withThrowingTaskGroup(of: NSImage?.self,   body: { group -> ImageCollection in
            let images = ImageCollection()
            for (i, imageURL) in imageURLStrings.compactMap({ URL(string: $0) }).enumerated() {
                
                // start a task for each url
                group.addTask {
                    do {
                        await plog.log("REQUESTED", index: i)
                        let image = try await downloadImage(from: imageURL)
                        await plog.log("RECEIVED ", index: i)
                        return image
                    } catch {
                        await plog.log("ERROR!!!!", index: i)
                        return nil
                    }
                }
            }
            
            // add them to the ImageCollection as they come in.
            for try await value in group {
                if let value {
                    await images.append(value)
                }
            }
            await plog.log(String(repeating: "-", count: columnCount * columnWidth))
            
            return images
        })
        
        // At this point allResults is an ImageCollection with all successfully
        // downloaded images.  Could do something interesting (save to file?) etc,
        // but for this program, just downloading them asynchronously was the
        // interesting part.
        await plog.log("Got \(await allResults.count)/\(imageURLStrings.count) images.")
        await plog.log("AsyncCLI1 Completed")
        
    }
}
