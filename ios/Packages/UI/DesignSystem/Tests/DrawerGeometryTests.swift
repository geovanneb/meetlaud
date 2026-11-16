import CoreGraphics
@testable import DesignSystem
import Testing

struct DrawerGeometryTests {
    @Test func `width scales on phones and caps on larger screens`() {
        #expect(DrawerGeometry.menuWidth(forContainer: 400) == 304)
        #expect(DrawerGeometry.menuWidth(forContainer: 800) == 340)
    }

    @Test func `progress stays between zero and one`() {
        #expect(DrawerGeometry.progress(isOpen: false, translation: 0, menuWidth: 300) == 0)
        #expect(DrawerGeometry.progress(isOpen: false, translation: 150, menuWidth: 300) == 0.5)
        #expect(DrawerGeometry.progress(isOpen: false, translation: 900, menuWidth: 300) == 1)
        #expect(DrawerGeometry.progress(isOpen: true, translation: 0, menuWidth: 300) == 1)
        #expect(DrawerGeometry.progress(isOpen: true, translation: -900, menuWidth: 300) == 0)
    }

    @Test func `empty width does not divide by zero`() {
        #expect(DrawerGeometry.progress(isOpen: true, translation: 10, menuWidth: 0) == 1)
    }

    @Test func `a short drag settles back`() {
        #expect(DrawerGeometry.settles(
            openFrom: false, translation: 40, predictedTranslation: 60, menuWidth: 300,
        ) == false)
    }

    @Test func `a quick flick opens`() {
        #expect(DrawerGeometry.settles(
            openFrom: false, translation: 60, predictedTranslation: 400, menuWidth: 300,
        ))
    }

    @Test func `a flick back closes`() {
        #expect(DrawerGeometry.settles(
            openFrom: true, translation: -60, predictedTranslation: -400, menuWidth: 300,
        ) == false)
    }

    @Test func `the menu settles at full size and full opacity`() {
        #expect(DrawerGeometry.menuScale(progress: 1) == 1)
        #expect(DrawerGeometry.menuOpacity(progress: 1) == 1)
        #expect(DrawerGeometry.menuScale(progress: 0) == 0.97)
    }
}
