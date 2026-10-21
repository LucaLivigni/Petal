import Foundation

/// Writes a PowerPoint file where every slide is one full-bleed picture.
nonisolated enum PPTXWriter {
    struct Slide { var jpeg: Data; var size: CGSize }

    static func write(_ slides: [Slide], to dest: URL) async throws {
        guard let first = slides.first else { throw PetalError("There are no pages to convert.") }
        let aspect = first.size.width / max(first.size.height, 1)
        let cx: Int, cy: Int
        if aspect >= 1 { cx = 12_192_000; cy = Int(Double(cx) / aspect) } else { cy = 6_858_000; cx = Int(Double(cy) * aspect) }

        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let relNS = "xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\""
        let emptyTree = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

        var files: [(path: String, data: Data)] = []
        func add(_ path: String, _ text: String) { files.append((path, Data((head + text).utf8))) }

        // Content types
        var overrides = "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/>"
            + "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/>"
            + "<Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>"
            + "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        for i in 1...slides.count { overrides += "<Override PartName=\"/ppt/slides/slide\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>" }
        add("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>\(overrides)</Types>")
        add("_rels/.rels", "<Relationships \(relNS)><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>")

        // Presentation
        var ids = "", presRels = "<Relationship Id=\"rId1\" Type=\"\(rel)/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/><Relationship Id=\"rId2\" Type=\"\(rel)/theme\" Target=\"theme/theme1.xml\"/>"
        for i in 1...slides.count {
            ids += "<p:sldId id=\"\(255 + i)\" r:id=\"rId\(i + 2)\"/>"
            presRels += "<Relationship Id=\"rId\(i + 2)\" Type=\"\(rel)/slide\" Target=\"slides/slide\(i).xml\"/>"
        }
        add("ppt/presentation.xml", "<p:presentation \(ns) saveSubsetFonts=\"1\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst><p:sldIdLst>\(ids)</p:sldIdLst><p:sldSz cx=\"\(cx)\" cy=\"\(cy)\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>")
        add("ppt/_rels/presentation.xml.rels", "<Relationships \(relNS)>\(presRels)</Relationships>")

        // Master, layout, theme
        add("ppt/slideMasters/slideMaster1.xml", "<p:sldMaster \(ns)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg><p:spTree>\(emptyTree)</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst></p:sldMaster>")
        add("ppt/slideMasters/_rels/slideMaster1.xml.rels", "<Relationships \(relNS)><Relationship Id=\"rId1\" Type=\"\(rel)/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"\(rel)/theme\" Target=\"../theme/theme1.xml\"/></Relationships>")
        add("ppt/slideLayouts/slideLayout1.xml", "<p:sldLayout \(ns) type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree>\(emptyTree)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>")
        add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", "<Relationships \(relNS)><Relationship Id=\"rId1\" Type=\"\(rel)/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/></Relationships>")
        add("ppt/theme/theme1.xml", theme)

        // Slides
        for (i, slide) in slides.enumerated() {
            let n = i + 1
            add("ppt/slides/slide\(n).xml", "<p:sld \(ns)><p:cSld><p:spTree>\(emptyTree)<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Page \(n)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>")
            add("ppt/slides/_rels/slide\(n).xml.rels", "<Relationships \(relNS)><Relationship Id=\"rId1\" Type=\"\(rel)/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"\(rel)/image\" Target=\"../media/image\(n).jpeg\"/></Relationships>")
            files.append(("ppt/media/image\(n).jpeg", slide.jpeg))
        }
        try await OfficePackage.write(files, to: dest)
    }

    private static let theme: String = {
        let fills = String(repeating: "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>", count: 3)
        let lines = String(repeating: "<a:ln w=\"6350\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/></a:ln>", count: 3)
        let effects = String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3)
        func accent(_ n: Int, _ hex: String) -> String { "<a:accent\(n)><a:srgbClr val=\"\(hex)\"/></a:accent\(n)>" }
        return "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Petal\"><a:themeElements>"
            + "<a:clrScheme name=\"Petal\"><a:dk1><a:sysClr val=\"windowText\" lastClr=\"000000\"/></a:dk1><a:lt1><a:sysClr val=\"window\" lastClr=\"FFFFFF\"/></a:lt1><a:dk2><a:srgbClr val=\"1F2937\"/></a:dk2><a:lt2><a:srgbClr val=\"F3F4F6\"/></a:lt2>"
            + accent(1, "FF8A1F") + accent(2, "4472C4") + accent(3, "34C759") + accent(4, "8E5CF6") + accent(5, "FF5A4E") + accent(6, "1AB5A8")
            + "<a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink><a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink></a:clrScheme>"
            + "<a:fontScheme name=\"Petal\"><a:majorFont><a:latin typeface=\"Helvetica Neue\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"Helvetica Neue\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme>"
            + "<a:fmtScheme name=\"Petal\"><a:fillStyleLst>\(fills)</a:fillStyleLst><a:lnStyleLst>\(lines)</a:lnStyleLst><a:effectStyleLst>\(effects)</a:effectStyleLst><a:bgFillStyleLst>\(fills)</a:bgFillStyleLst></a:fmtScheme>"
            + "</a:themeElements></a:theme>"
    }()
}
