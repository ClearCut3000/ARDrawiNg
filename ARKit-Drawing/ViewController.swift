import ARKit

class ViewController: UIViewController {

  // MARK: - Outlets
  @IBOutlet var sceneView: ARSCNView!

  // MARK: - Properties
  /// Visualize planes
  var arePlanesHidden = false {
    didSet{
      planeNodes.forEach { $0.isHidden = arePlanesHidden }
    }
  }

  /// Adding node at user's point of tap.
  /// - Parameters:
  ///   - node: node^ that must be added
  ///   - point: point of user's touch
  func addNode(_ node: SCNNode, at point: CGPoint){
    if #available(iOS 13, *){
      guard let query = sceneView.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) else { return }
      guard let result = sceneView.session.raycast(query).first else { return }
      node.simdTransform = result.worldTransform
      addNodeToSceneRoot(node)
    } else {
      guard let hitResult = sceneView.hitTest(point, types: .existingPlaneUsingExtent).first else { return }
      guard let anchor = hitResult.anchor as? ARPlaneAnchor, anchor.alignment == .horizontal else { return }
      node.simdTransform = hitResult.worldTransform
      addNodeToSceneRoot(node)
    }
  }

  func addNode(_ node: SCNNode, to parentNode: SCNNode){
    // Check that objects are not too close
    if let lastNode = lastNode {
      let lastPosition = lastNode.position
      let newPosition = node.position
      let x = lastPosition.x - newPosition.x
      let y = lastPosition.y - newPosition.y
      let z = lastPosition.z - newPosition.z
      let distanceSquare = x * x + y * y + z * z
      let minimumDistanceSquare = minimumDistance * minimumDistance
      guard minimumDistanceSquare < distanceSquare else { return }
    }

    // Clone node to separate copies of object
    let clonedNode = node.clone()

    // Remember last placed node
    lastNode = clonedNode

    // Remember object plased for undo
    objectsPlased.append(clonedNode)

    // Add cloned node to scene
    parentNode.addChildNode(clonedNode)
  }

  let configuration = ARWorldTrackingConfiguration()

  // Last node, placed by user
  var lastNode: SCNNode?

  // Minimum distance between objects placed when moving
  let minimumDistance: Float = 0.05

  /// The node for an object currently selected by user
  var selectedNode: SCNNode?

  enum ObjectPlacementMode {
    case freeform, plane, image
  }

  var objectMode: ObjectPlacementMode = .freeform

  /// Array of  and object plased
  var objectsPlased = [SCNNode]()

  /// Array of planes found
  var planeNodes = [SCNNode]()


  // MARK: - Methods
  /// Add node in front of camera
  func addNodeInFront (_ node: SCNNode){
    // Get current camera's frame
    guard let frame = sceneView.session.currentFrame else { return }
    // Get transform property of camera
    let transform = frame.camera.transform

    var translation = matrix_identity_float4x4

    // Translate to 20 cm on z-axis
    translation.columns.3.z = -0.2

    // Rotate by .pi/2 on z-axis
    translation.columns.0.x = 0
    translation.columns.1.x = -1
    translation.columns.0.y = 1
    translation.columns.1.y = 0
    // Assign transform to the node
    node.simdTransform = matrix_multiply(transform, translation)

  }

  func addNodeToImage(_ node: SCNNode, at point: CGPoint) {
    guard let result = sceneView.hitTest(point, options: [:]).first else { return }
    guard node.name == "image" else { return }
    node.transform = result.node.worldTransform
    node.eulerAngles.x = 0
    addNodeToSceneRoot(node)
  }

  func addNodeToSceneRoot(_ node: SCNNode){
    addNode(node, to: sceneView.scene.rootNode)

  }


  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    process(touches)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    process(touches)
  }

  func process(_ touches: Set<UITouch>) {
    guard let touch = touches.first, let selectedNode = selectedNode else { return }
    let point = touch.location(in: sceneView)
    switch objectMode {
    case  .freeform:
      addNodeInFront(selectedNode)
    case .image:
      addNodeToImage(selectedNode, at: point)
    case  .plane:
      addNode(selectedNode, at: point)
    }
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if segue.identifier == "showOptions" {
      let optionsViewController = segue.destination as! OptionsContainerViewController
      optionsViewController.delegate = self
    }
  }

  func reloadConfiguration() {
    configuration.detectionImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil)
    configuration.planeDetection = .horizontal
    sceneView.session.run(configuration)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    sceneView.delegate = self
    sceneView.autoenablesDefaultLighting = true
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reloadConfiguration()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sceneView.session.pause()
  }

  // MARK: - Actions
  @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
    switch sender.selectedSegmentIndex {
    case 0:
      objectMode = .freeform
      arePlanesHidden = true
    case 1:
      objectMode = .plane
      arePlanesHidden = false
    case 2:
      objectMode = .image
      arePlanesHidden = true
    default:
      break
    }
  }
}

// MARK: - OptionsViewControllerDelegate
extension ViewController: OptionsViewControllerDelegate {

  func objectSelected(node: SCNNode) {
    dismiss(animated: true, completion: nil)
    selectedNode = node
  }

  func togglePlaneVisualization() {
    dismiss(animated: true, completion: nil)
    guard objectMode == .plane else { return }
    arePlanesHidden.toggle()
  }

  func undoLastObject() {

  }

  func resetScene() {
    dismiss(animated: true, completion: nil)
  }
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate{

  func createFloor(with size: CGSize, opacity: CGFloat = 0.25) -> SCNNode{
    // Get estimated plane size
    let  plane = SCNPlane(width: size.width, height: size.height)
    plane.firstMaterial?.diffuse.contents = UIColor.green
    let planeNode = SCNNode(geometry: plane)
    planeNode.eulerAngles.x -= .pi/2
    planeNode.opacity = opacity
    return planeNode
  }

  func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor){
    // Put plane at the image
    let size = anchor.referenceImage.physicalSize
    let coverNode = createFloor(with: size, opacity: 0.1)
    coverNode.name = "image"
    node.addChildNode(coverNode)
  }

  func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor){
    let extent = anchor.extent
    let size = CGSize(width: CGFloat(extent.x), height: CGFloat(extent.z))
    let planeNode = createFloor(with: size)
    planeNode.isHidden = arePlanesHidden
    // Add plane node to list of plane nodes
    planeNodes.append(planeNode)
    node.addChildNode(planeNode)
  }

  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    switch anchor {
    case let imageAnchor as ARImageAnchor:
      nodeAdded(node, for: imageAnchor)
    case let planeAnchor as ARPlaneAnchor:
      nodeAdded(node, for: planeAnchor)
    default:
      print(#line, #function, "Unknown anchor found!")
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    switch anchor{
    case is ARImageAnchor:
      break
    case let planeAnchor as ARPlaneAnchor:
      updateFloor(for: node, anchor: planeAnchor)
    default:
      print("Unknown type of \(anchor) found!")
    }
  }

  func updateFloor(for node: SCNNode, anchor: ARPlaneAnchor) {
    guard let planeNode = node.childNodes.first, let plane = planeNode.geometry as? SCNPlane else { return }
    // Get estimated plane size
    let extent = anchor.extent
    plane.width = CGFloat(extent.x)
    plane.height = CGFloat(extent.z)
    // Positioning node in the center
    planeNode.simdPosition = anchor.center

  }
}
