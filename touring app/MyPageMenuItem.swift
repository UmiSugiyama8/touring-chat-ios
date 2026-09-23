import SwiftUI

struct MyPageMenuItem: Identifiable, Hashable {
    let id=UUID()
    var title:String
    var systemImage:String
    var color:Color
}
