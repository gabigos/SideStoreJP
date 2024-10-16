//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas
import EmotionalDamage
import minimuxer

import AltStoreCore
import UniformTypeIdentifiers

let pairingFileName = "ALTPairingFile.mobiledevicepairing"

final class LaunchViewController: RSTLaunchViewController, UIDocumentPickerDelegate {
    private var didFinishLaunching = false
    
    private var destinationViewController: UIViewController!
    
    override var launchConditions: [RSTLaunchCondition] {
        let isDatabaseStarted = RSTLaunchCondition(condition: { DatabaseManager.shared.isStarted }) { (completionHandler) in
            DatabaseManager.shared.start(completionHandler: completionHandler)
        }
        return [isDatabaseStarted]
    }
    
    override var childForStatusBarStyle: UIViewController? {
        return self.children.first
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return self.children.first
    }
    
    override func viewDidLoad() {
        defer {
            self.destinationViewController = self.storyboard!.instantiateViewController(withIdentifier: "tabBarController") as! TabBarController
        }
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        
        if #available(iOS 17, *), !UserDefaults.standard.sidejitenable {
            DispatchQueue.global().async {
                self.isSideJITServerDetected() { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success():
                            let dialogMessage = UIAlertController(
                                title: "SideJITサーバー検出", 
                                message: "SideJITサーバーを有効にしますか？", 
                                preferredStyle: .alert
                            )
                            let ok = UIAlertAction(title: "OK", style: .default) { _ in
                                UserDefaults.standard.sidejitenable = true
                            }
                            let cancel = UIAlertAction(title: "キャンセル", style: .cancel)
                            dialogMessage.addAction(ok)
                            dialogMessage.addAction(cancel)
                            self.present(dialogMessage, animated: true, completion: nil)
                        case .failure(_):
                            print("SideJITサーバーが見つかりません")
                        }
                    }
                }
            }
        }
        
        if #available(iOS 17, *), UserDefaults.standard.sidejitenable {
            DispatchQueue.global().async {
                self.askfornetwork()
            }
            print("SideJITサーバーが有効化されました")
        }
        
        #if !targetEnvironment(simulator)
        start_em_proxy(bind_addr: Consts.Proxy.serverURL)
        
        guard let pf = fetchPairingFile() else {
            displayError("ペアリングファイルが見つかりません")
            return
        }
        start_minimuxer_threads(pf)
        #endif
    }
    
    func askfornetwork() {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        var SJSURL = address
        
        if SJSURL.isEmpty {
            SJSURL = "http://sidejitserver._http._tcp.local:8080"
        }
        
        let url = URL(string: "\(SJSURL)/re/")!
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            print(data ?? "ネットワークからの応答なし")
        }
        task.resume()
    }
    
    func isSideJITServerDetected(completion: @escaping (Result<Void, Error>) -> Void) {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        var SJSURL = address
        
        if SJSURL.isEmpty {
            SJSURL = "http://sidejitserver._http._tcp.local:8080"
        }
        
        let url = URL(string: SJSURL)!
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                print("SideJITサーバーが見つかりません")
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
        task.resume()
    }
    
    func fetchPairingFile() -> String? {
        let documentsPath = FileManager.default.documentsDirectory.appendingPathComponent("/\(pairingFileName)")
        if FileManager.default.fileExists(atPath: documentsPath.path), 
           let contents = try? String(contentsOf: documentsPath), 
           !contents.isEmpty {
            print("ペアリングファイルを \(documentsPath.path) から読み込みました")
            return contents
        } else {
            let dialogMessage = UIAlertController(
                title: "ペアリングファイル", 
                message: "ペアリングファイルを選択するか、「ヘルプ」を押してください。", 
                preferredStyle: .alert
            )
            let ok = UIAlertAction(title: "OK", style: .default) { _ in
                var types = UTType.types(tag: "plist", tagClass: .filenameExtension, conformingTo: nil)
                types.append(contentsOf: UTType.types(tag: "mobiledevicepairing", tagClass: .filenameExtension, conformingTo: .data))
                types.append(.xml)
                
                let documentPickerController = UIDocumentPickerViewController(forOpeningContentTypes: types)
                documentPickerController.shouldShowFileExtensions = true
                documentPickerController.delegate = self
                self.present(documentPickerController, animated: true, completion: nil)
            }
            
            let wikiOption = UIAlertAction(title: "ヘルプ", style: .default) { _ in
                if let url = URL(string: "https://docs.sidestore.io/docs/getting-started/pairing-file") {
                    UIApplication.shared.open(url)
                }
                sleep(2)
                exit(0)
            }
            
            dialogMessage.addAction(wikiOption)
            dialogMessage.addAction(ok)
            self.present(dialogMessage, animated: true, completion: nil)
            
            return nil
        }
    }
    
    func displayError(_ msg: String) {
        print(msg)
        let dialogMessage = UIAlertController(
            title: "エラー", 
            message: msg, 
            preferredStyle: .alert
        )
        self.present(dialogMessage, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        if let pairingString = try? String(contentsOf: url), !pairingString.isEmpty {
            let pairingFile = FileManager.default.documentsDirectory.appendingPathComponent(pairingFileName)
            try? pairingString.write(to: pairingFile, atomically: true, encoding: .utf8)
            start_minimuxer_threads(pairingString)
        } else {
            displayError("ペアリングファイルの読み込みに失敗しました")
        }
        controller.dismiss(animated: true, completion: nil)
    }
    
    func start_minimuxer_threads(_ pairing_file: String) {
        do {
            try start(pairing_file, FileManager.default.documentsDirectory.absoluteString)
        } catch {
            try? FileManager.default.removeItem(at: FileManager.default.documentsDirectory.appendingPathComponent(pairingFileName))
            displayError("minimuxerの起動に失敗しました: \(error.localizedDescription)")
        }
    }
}
