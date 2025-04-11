import SwiftUI

struct CalculatorView: View {
    @State private var displayValue = "0"
    @State private var currentOperation: Operation?
    @State private var previousValue: Double = 0
    @State private var isNewNumber = true
    @State private var isAuthenticated = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // 从 UserDefaults 获取密码
    private var correctPassword: String {
        UserDefaults.standard.string(forKey: "computerPassword") ?? "1234"
    }
    
    enum Operation {
        case add, subtract, multiply, divide
    }
    
    enum CalculatorButtonType: Hashable {
        case clear, plusMinus, percent
        case divide, multiply, subtract, add, equals
        case decimal
        case number(Int)
        
        func hash(into hasher: inout Hasher) {
            switch self {
            case .clear:
                hasher.combine(0)
            case .plusMinus:
                hasher.combine(1)
            case .percent:
                hasher.combine(2)
            case .divide:
                hasher.combine(3)
            case .multiply:
                hasher.combine(4)
            case .subtract:
                hasher.combine(5)
            case .add:
                hasher.combine(6)
            case .equals:
                hasher.combine(7)
            case .decimal:
                hasher.combine(8)
            case .number(let value):
                hasher.combine(9)
                hasher.combine(value)
            }
        }
        
        static func == (lhs: CalculatorButtonType, rhs: CalculatorButtonType) -> Bool {
            switch (lhs, rhs) {
            case (.clear, .clear), (.plusMinus, .plusMinus), (.percent, .percent),
                 (.divide, .divide), (.multiply, .multiply), (.subtract, .subtract),
                 (.add, .add), (.equals, .equals), (.decimal, .decimal):
                return true
            case (.number(let lhsValue), .number(let rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }
    }
    
    let buttons: [[CalcButton]] = [
        [.init(title: "C", backgroundColor: .gray, foregroundColor: .white, type: .clear),
         .init(title: "±", backgroundColor: .gray, foregroundColor: .white, type: .plusMinus),
         .init(title: "%", backgroundColor: .gray, foregroundColor: .white, type: .percent),
         .init(title: "÷", backgroundColor: .orange, foregroundColor: .white, type: .divide)],
        
        [.init(title: "7", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(7)),
         .init(title: "8", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(8)),
         .init(title: "9", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(9)),
         .init(title: "×", backgroundColor: .orange, foregroundColor: .white, type: .multiply)],
        
        [.init(title: "4", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(4)),
         .init(title: "5", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(5)),
         .init(title: "6", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(6)),
         .init(title: "-", backgroundColor: .orange, foregroundColor: .white, type: .subtract)],
        
        [.init(title: "1", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(1)),
         .init(title: "2", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(2)),
         .init(title: "3", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(3)),
         .init(title: "+", backgroundColor: .orange, foregroundColor: .white, type: .add)],
        
        [.init(title: "0", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .number(0)),
         .init(title: ".", backgroundColor: Color.gray.opacity(0.7), foregroundColor: .white, type: .decimal),
         .init(title: "=", backgroundColor: .orange, foregroundColor: .white, type: .equals)]
    ]
    
    var body: some View {
        ZStack {
            if isAuthenticated {
                MainView()
                    .transition(.opacity.combined(with: .scale))
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 12) {
                    Spacer()
                    
                    // 显示区域
                    HStack {
                        Spacer()
                        Text(displayValue)
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                            .padding()
                    }
                    
                    // 提示文本
                    // Text("请输入密码")
                    //     .foregroundColor(.white)
                    //     .font(.headline)
                    //     .padding(.bottom, 20)
                    
                    // 按钮网格
                    ForEach(0..<buttons.count, id: \.self) { rowIndex in
                        HStack(spacing: 12) {
                            ForEach(buttons[rowIndex]) { button in
                                CalcButtonView(button: button, action: {
                                    self.buttonTapped(button.type)
                                })
                            }
                        }
                    }
                }
                .padding(.bottom)
                .alert("错误", isPresented: $showError) {
                    Button("确定", role: .cancel) {
                        displayValue = "0"
                        currentOperation = nil
                        previousValue = 0
                        isNewNumber = true
                    }
                } message: {
                    Text(errorMessage)
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isAuthenticated)
    }
    
    func buttonTapped(_ type: CalculatorButtonType) {
        switch type {
        case .clear:
            displayValue = "0"
            currentOperation = nil
            previousValue = 0
            isNewNumber = true
            
        case .plusMinus:
            if let value = Double(displayValue) {
                displayValue = String(-value)
            }
            
        case .percent:
            if let value = Double(displayValue) {
                displayValue = String(value / 100)
            }
            
        case .divide:
            if let value = Double(displayValue) {
                previousValue = value
                currentOperation = .divide
                isNewNumber = true
            }
            
        case .multiply:
            if let value = Double(displayValue) {
                previousValue = value
                currentOperation = .multiply
                isNewNumber = true
            }
            
        case .subtract:
            if let value = Double(displayValue) {
                previousValue = value
                currentOperation = .subtract
                isNewNumber = true
            }
            
        case .add:
            if let value = Double(displayValue) {
                previousValue = value
                currentOperation = .add
                isNewNumber = true
            }
            
        case .equals:
            if let operation = currentOperation,
               let currentValue = Double(displayValue) {
                let result: Double
                switch operation {
                case .add:
                    result = previousValue + currentValue
                case .subtract:
                    result = previousValue - currentValue
                case .multiply:
                    result = previousValue * currentValue
                case .divide:
                    result = previousValue / currentValue
                }
                
                // 格式化结果，如果是整数则不显示小数点
                if result.truncatingRemainder(dividingBy: 1) == 0 {
                    displayValue = String(Int(result))
                } else {
                    displayValue = String(result)
                }
                
                currentOperation = nil
                isNewNumber = true
                
                // 验证密码
                if displayValue == correctPassword {
                    isAuthenticated = true
                } else {
                    showError = true
                    errorMessage = "密码错误，请重试"
                }
            } else {
                // 直接验证当前显示的值
                if displayValue == correctPassword {
                    isAuthenticated = true
                }
            }
            
        case .decimal:
            if !displayValue.contains(".") {
                displayValue += "."
            }
            
        case .number(let digit):
            if isNewNumber {
                displayValue = String(digit)
                isNewNumber = false
            } else {
                displayValue += String(digit)
            }
            
            // 检查密码
            if displayValue == correctPassword {
                isAuthenticated = true
            }
        }
    }
}

struct CalcButton: Hashable, Identifiable {
    let id = UUID()
    let title: String
    let backgroundColor: Color
    let foregroundColor: Color
    let type: CalculatorView.CalculatorButtonType
    
    static func == (lhs: CalcButton, rhs: CalcButton) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct CalcButtonView: View {
    let button: CalcButton
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(button.title)
                .font(.system(size: 32))
                .frame(width: button.title == "0" ? 160 : 80, height: 80)
                .background(button.backgroundColor)
                .foregroundColor(button.foregroundColor)
                .cornerRadius(40)
        }
    }
}

#Preview {
    CalculatorView()
} 
