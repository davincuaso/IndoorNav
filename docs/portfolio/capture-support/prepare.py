"""Build-only fixture injection. Original views/renderers remain unchanged."""
import json, os, pathlib, sys

kind=sys.argv[1]
root=pathlib.Path('app')
folder={'splitsmart':'SplitSmart','pantrychef':'PantryChef','posturepal':'PosturePal','indoornav':'IndoorNav'}[kind]
src=root/folder
def patch(file, old, new):
    p=src/file
    text=p.read_text()
    assert old in text, (file,old)
    p.write_text(text.replace(old,new,1))

if kind=='splitsmart':
    patch('App/SplitSmartApp.swift','BillViewModel()', 'portfolioBill()')
    (src/'PortfolioFixture.swift').write_text('''import Foundation
@MainActor func portfolioBill() -> BillViewModel {
    let vm = BillViewModel()
    vm.clearSession()
    vm.groupName = "Dinner with friends"
    let people = ["Alex", "Bea", "Chris"].map { vm.addPerson(name: $0) }
    for (name,price) in [("Chicken rice",Decimal(18)),("Vegetables",Decimal(12)),("Drinks",Decimal(6))] {
        let item = vm.addItem(name: name, price: price)
        vm.assignPeople(people, toItemID: item.id)
    }
    return vm
}
''')
elif kind=='pantrychef':
    patch('Views/ContentView.swift', '    // MARK: - Body', '''    init() {
        if ProcessInfo.processInfo.arguments.contains("--sample-ingredients") {
            _recognizedIngredients = State(initialValue: ["salmon"])
        }
    }

    // MARK: - Body''')
elif kind=='indoornav':
    patch('MainTabView.swift', 'var selectedTab: AppTab = .ar','var selectedTab: AppTab = .scans')
    patch('IndoorNavApp.swift','    var body:', '    init() { portfolioMesh() }\n    var body:')
    vertices=[]; normals=[]; indices=[]
    def plane(origin,u,v,n,steps=12):
        start=len(vertices)
        for a in range(steps+1):
            for b in range(steps+1):
                vertices.append(dict(zip('xyz',[origin[i]+u[i]*a/steps+v[i]*b/steps for i in range(3)])))
                normals.append(dict(zip('xyz',n)))
        for a in range(steps):
            for b in range(steps):
                k=start+a*(steps+1)+b
                indices.extend([k,k+1,k+steps+1,k+1,k+steps+2,k+steps+1])
    plane([-2,0,-2],[4,0,0],[0,0,4],[0,1,0])
    plane([-2,0,-2],[4,0,0],[0,2.6,0],[0,0,1])
    plane([-2,0,-2],[0,0,4],[0,2.6,0],[1,0,0])
    plane([-.8,.8,-.6],[1.6,0,0],[0,0,1],[0,1,0],8)
    plane([-.8,0,-.6],[1.6,0,0],[0,.8,0],[0,0,1],8)
    plane([-.8,0,-.6],[0,0,1],[0,.8,0],[1,0,0],8)
    mesh={'chunks':[{'vertices':vertices,'normals':normals,'indices':indices,'transformData':[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}], 'boundingBox':dict(minX=-2,minY=0,minZ=-2,maxX=2,maxY=2.6,maxZ=2),'createdAt':800000000}
    (src/'sample-mesh.json').write_text(json.dumps(mesh))
    (src/'PortfolioFixture.swift').write_text('''import Foundation
@MainActor func portfolioMesh() {
    let zone = ZoneStore.shared.createZone(name: "Sample room", description: "Simulator fixture, not a LiDAR capture")
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("IndoorNavMeshes")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try! Data(contentsOf: Bundle.main.url(forResource: "sample-mesh", withExtension: "json")!)
    try! data.write(to: dir.appendingPathComponent("\\(zone.id.uuidString).scanmesh"))
}
''')

pathlib.Path('CaptureTests').mkdir(exist_ok=True)
tests={
'splitsmart':'''wait(app.navigationBars["Dinner with friends"])
        shot("01-bill-entry")
        let calculate=app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Calculate Split")).firstMatch
        wait(calculate); calculate.tap()
        wait(app.navigationBars["Summary"])
        shot("02-split-summary")''',
'posturepal':'''wait(app.navigationBars["PosturePal"])
        shot("01-camera-permission")
        app.navigationBars["PosturePal"].buttons.firstMatch.tap()
        wait(app.navigationBars["Settings"])
        shot("02-settings")''',
'pantrychef':'''wait(app.navigationBars["PantryChef"])
        shot("01-add-photo")
        app.terminate()
        app.launchArguments=["--sample-ingredients"]
        app.launch()
        wait(app.buttons["Find Recipes"]); app.buttons["Find Recipes"].tap()
        XCTAssertTrue(app.staticTexts["Recipes"].waitForExistence(timeout: 150), app.debugDescription)
        app.swipeUp()
        shot("02-live-recipe-results")
        let recipe = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "salmon")).firstMatch
        if recipe.exists { recipe.tap(); shot("03-recipe-detail") }''',
'indoornav':'''wait(app.navigationBars["My Scans"])
        shot("01-scan-library")
        wait(app.staticTexts["Sample room"]); app.staticTexts["Sample room"].firstMatch.tap()
        wait(app.buttons["Done"])
        sleep(4)
        XCTAssertFalse(app.staticTexts["Unable to Load"].exists)
        shot("02-sample-mesh-viewer")'''
}
pathlib.Path('CaptureTests/CaptureTests.swift').write_text('''import XCTest
final class CaptureTests: XCTestCase {
    func wait(_ element: XCUIElement) { XCTAssertTrue(element.waitForExistence(timeout: 30)) }
    func shot(_ name: String) {
        sleep(2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testCapture() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        '''+tests[kind]+'''
    }
}
''')
project={'name':'PortfolioCapture','options':{'deploymentTarget':{'iOS':'17.0'}},'settings':{'base':{'SWIFT_VERSION':'5.0','CODE_SIGNING_ALLOWED':'NO','TARGETED_DEVICE_FAMILY':'1','GENERATE_INFOPLIST_FILE':'YES'}},'targets':{
'CaptureApp':{'type':'application','platform':'iOS','sources':[{'path':str(src),'excludes':['**/Info.plist','**/*.entitlements']}],'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'com.davincuaso.capture.'+kind,'INFOPLIST_KEY_NSCameraUsageDescription':'Capture app demonstration screens','INFOPLIST_KEY_NSPhotoLibraryUsageDescription':'Choose ingredient photos','INFOPLIST_KEY_NSHealthShareUsageDescription':'Optional posture tracking','INFOPLIST_KEY_NSHealthUpdateUsageDescription':'Optional posture tracking'}}},
'CaptureTests':{'type':'bundle.ui-testing','platform':'iOS','sources':['CaptureTests'],'dependencies':[{'target':'CaptureApp'}],'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'com.davincuaso.capture.tests.'+kind}}}},'schemes':{'PortfolioCapture':{'build':{'targets':{'CaptureApp':'all','CaptureTests':['test']}},'test':{'targets':['CaptureTests'],'gatherCoverageData':False}}}}
pathlib.Path('project.json').write_text(json.dumps(project,indent=2))
