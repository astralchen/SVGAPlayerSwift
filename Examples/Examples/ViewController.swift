//
//  ViewController.swift
//  Examples
//
//  Created by Sondra on 2026/3/23.
//

import UIKit
import SVGAPlayer

class ViewController: UIViewController {

    @IBOutlet weak var imageView: SVGAPlayerView!

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.contentMode = .scaleAspectFit
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        imageView.play(named: "banner")
    }
}
