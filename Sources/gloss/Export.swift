import GlossLint
import GlossModel

/// What `gloss interface --json` writes: the interface with the lint's assessments beside it, one
/// document from one reading.
///
/// The JSON form is the stable surface for other tools; the model and the lint are built apart and
/// only meet here, side by side.
struct Export: Encodable {
    /// The version of this JSON shape. It changes only when a field is removed or changes meaning.
    ///
    /// Version 2 moved `requiresDoc`, `exemption`, and `findings` out of each contract into `assessments`.
    var schema = 2
    /// The scanned paths, in the order they were read and as they are reported.
    var files: [String]
    /// One contract per declaration, in file order and then source order.
    var contracts: [Contract]
    /// One assessment per contract, at the same index.
    var assessments: [Assessment]
    /// The dependency graph drawn from the contracts' mentions.
    var graph: Graph

    /// Puts an interface and its assessments side by side.
    ///
    /// - Parameters:
    ///   - interface: The contracts and their graph.
    ///   - assessments: One assessment per contract, at the same index.
    init(_ interface: Interface, assessments: [Assessment]) {
        files = interface.files
        contracts = interface.contracts
        self.assessments = assessments
        graph = interface.graph
    }
}
