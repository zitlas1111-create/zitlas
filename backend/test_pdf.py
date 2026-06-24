from pypdf import PdfReader

# List your PDF files here
pdf_files = [
    "weight_loss/wl1.pdf",
    "weight_loss/wl2.pdf"
]

for pdf_path in pdf_files:
    print("\n" + "=" * 80)
    print(f"Testing PDF: {pdf_path}")
    print("=" * 80)

    try:
        reader = PdfReader(pdf_path)

        print(f"Pages: {len(reader.pages)}")

        # Extract text from first page
        text = reader.pages[0].extract_text()

        if text:
            print("\nFirst 2000 characters:\n")
            print(text[:2000])
        else:
            print("\n❌ No text extracted from first page.")
            print("This PDF may require OCR.")

    except Exception as e:
        print(f"\n❌ Error reading PDF: {e}")