import SwiftUI

struct DelayPickerView: View {
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void

    private let minutesOptions: [Int] = Array(stride(from: 5, through: 60, by: 5))

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("何分遅れる？")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(minutesOptions, id: \.self) { m in
                            Button {
                                onSelect("\(m)分遅れる")
                                isPresented = false
                            } label: {
                                Text("\(m)分")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }

                        Button {
                            onSelect("1時間以上遅れる")
                            isPresented = false
                        } label: {
                            Text("1時間以上")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("遅れる")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
