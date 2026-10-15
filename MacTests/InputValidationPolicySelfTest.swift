import Foundation

@main struct InputValidationPolicySelfTest {
    static func main() {
        precondition(InputValidationPolicy.coordinate(.nan) == nil)
        precondition(InputValidationPolicy.coordinate(.infinity) == nil)
        precondition(InputValidationPolicy.coordinate(-4) == 0)
        precondition(InputValidationPolicy.coordinate(10) == 1)
        precondition(InputValidationPolicy.scroll(1e300, scale: 2) == 32768)
        precondition(InputValidationPolicy.scroll(-1e300, scale: 2) == -32768)
        precondition(InputValidationPolicy.scroll(20, scale: 2) == 10)
        precondition(InputValidationPolicy.scroll(.infinity, scale: 1) == nil)
        precondition(InputValidationPolicy.scroll(10, scale: 0) == nil)
        print("Input validation: nonfinite rejection, normalized coordinates and safe scroll conversion PASS")
    }
}
