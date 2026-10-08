import PhotosUI
import SwiftData
import SwiftUI
import VisionKit

/// Step one of syllabus import: pick the class, then a file, photos or a scan.
/// Pushes the review screen once items have been detected.
struct SyllabusImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.sortIndex) private var courses: [Course]

    @State private var model: SyllabusImportModel
    @State private var isPickingFile = false
    @State private var isScanning = false
    @State private var isAddingCourse = false
    @State private var photoSelection: [PhotosPickerItem] = []
    /// The import in flight; cancelled when the sheet closes.
    @State private var importTask: Task<Void, Never>?

    init(course: Course? = nil) {
        _model = State(initialValue: SyllabusImportModel(course: course))
    }

    private var isWorking: Bool {
        if case .working = model.phase { true } else { false }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick the class, then its syllabus. The app finds the assignments, quizzes, exams and readings for you to review. Everything is read on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Class")
                        CourseChips(courses: courses, selection: $model.course) {
                            isAddingCourse = true
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Syllabus")
                        sourceCard
                        Text(model.course == nil
                             ? "Choose a class first."
                             : "PDF, Word (.docx), text or photos · up to \(ByteCountFormatter.string(fromByteCount: SyllabusTextExtractor.maxFileSize, countStyle: .file))")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryText)
                            .padding(.horizontal, 4)
                    }

                    if let error = model.error {
                        ErrorCard(error: error)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.snappy, value: model.error)
            }
            .background { DuskBackground() }
            .overlay {
                if case .working(let message) = model.phase {
                    WorkingOverlay(message: message)
                }
            }
            .disabled(isWorking)
            .navigationTitle("Import Syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        importTask?.cancel()
                        dismiss()
                    } label: { Label("Cancel", appIcon: .close) }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { model.phase == .reviewing },
                set: { if !$0 { model.startOver() } }
            )) {
                ImportReviewView(model: model) { dismiss() }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: SyllabusTextExtractor.supportedTypes) { result in
                switch result {
                case .success(let url):
                    startImport { await model.importFile(url) }
                case .failure(let error):
                    model.error = .unreadable(error.localizedDescription)
                }
            }
            .onChange(of: photoSelection) { _, items in
                guard !items.isEmpty else { return }
                photoSelection = []
                startImport {
                    model.prepareForPhotos(count: items.count)
                    var photos: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) { photos.append(data) }
                    }
                    await model.importPhotos(photos)
                }
            }
            .fullScreenCover(isPresented: $isScanning) {
                DocumentScanner { images in
                    isScanning = false
                    guard !images.isEmpty else { return }
                    startImport { await model.importScan(images) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isAddingCourse) {
                CourseEditorSheet { model.course = $0 }
            }
        }
        .interactiveDismissDisabled(isWorking || model.phase == .reviewing)
        .onDisappear { importTask?.cancel() }
    }

    /// Runs one import at a time.
    private func startImport(_ work: @escaping @MainActor () async -> Void) {
        guard importTask == nil, !isWorking else { return }
        importTask = Task {
            await work()
            importTask = nil
        }
    }

    private var sourceCard: some View {
        VStack(spacing: 0) {
            SourceRow(title: "Choose File", icon: .notes) { isPickingFile = true }
            Divider()
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 10, matching: .images) {
                // No photo glyph in the app's icon set; SF Symbol fallback.
                SourceRowLabel(title: "Photo Library", fallbackSymbol: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            if VNDocumentCameraViewController.isSupported {
                Divider()
                SourceRow(title: "Scan Document", icon: .scan) { isScanning = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .glassCard()
        .disabled(model.course == nil)
        .opacity(model.course == nil ? 0.5 : 1)
    }
}

private struct SourceRow: View {
    let title: String
    let icon: AppIcon.Name
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SourceRowLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

private struct SourceRowLabel: View {
    let title: String
    var icon: AppIcon.Name?
    var fallbackSymbol: String?

    var body: some View {
        HStack {
            if let icon {
                RowLabel(title, icon: icon)
            } else {
                RowLabel.SymbolFallback(title: title, systemImage: fallbackSymbol ?? "")
            }
            Spacer()
            AppIcon(.forward, size: 16)
                .foregroundStyle(Palette.mutedNumber)
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
    }
}

private struct ErrorCard: View {
    let error: SyllabusImportError

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIcon(.info, size: 24)
                .foregroundStyle(Palette.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text(error.errorDescription ?? "Something went wrong.")
                    .font(.subheadline.weight(.semibold))
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

private struct WorkingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 280)
        .glassCard(cornerRadius: 28)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) { SyllabusImportSheet() }
        .modelContainer(.preview)
}
