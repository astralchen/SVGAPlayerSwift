//
//  ViewController.swift
//  Examples
//
//  Created by Sondra on 2026/3/23.
//

import UIKit
import SVGAPlayer

class ViewController: UIViewController {

    @IBOutlet weak var imageView: SVGAImageView!

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.contentMode = .scaleAspectFit
    }

    override func viewDidAppear(_ animated: Bool) {
        loadSVGA()
    }

    private func loadSVGA() {
        // Step 1: 确认 bundle 里能找到文件

        let fileName = "banner"

        if let url = Bundle.main.url(forResource: fileName, withExtension: "svga") {
            print("[SVGA] bundle 文件路径: \(url.path)")
        } else {
            print("[SVGA] ❌ bundle 里找不到 banner.svga，请检查 Target Membership")
            return
        }

        // Step 2: 直接用 parser 解析，捕获具体错误
        Task {
            do {
                let entity = try await SVGAParser.shared.parse(named: fileName, in: nil)
                print("[SVGA] ✅ 解析成功 fps=\(entity.fps) frames=\(entity.frames) sprites=\(entity.sprites.count) size=\(entity.videoSize)")

                guard entity.fps > 0 else {
                    print("[SVGA] ❌ fps=0，无法播放")
                    return
                }
                guard entity.frames > 0 else {
                    print("[SVGA] ❌ frames=0，无法播放")
                    return
                }

                // Step 3: 手动赋值并播放
                imageView.videoItem = entity
                imageView.startAnimation()
                print("[SVGA] ▶️ startAnimation 已调用")
                print("[SVGA] imageView.frame=\(imageView.frame) bounds=\(imageView.bounds)")
            } catch {
                print("[SVGA] ❌ 解析失败: \(error)")
            }
        }
    }
}
