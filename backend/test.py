import os
from dotenv import load_dotenv
from google import genai

load_dotenv()

api_key = os.getenv("GEMINI_API_KEY")

print("=" * 50)
print("Gemini Key Found:", api_key is not None)

if api_key:
    print("Key Prefix:", api_key[:10] + "...")
else:
    print("ERROR: GEMINI_API_KEY not found in .env")
    exit()

print("=" * 50)

try:
    client = genai.Client(api_key=api_key)

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents="Say hello in one sentence."
    )

    print("\nSUCCESS!")
    print("=" * 50)
    print(response.text)

except Exception as e:
    print("\nERROR!")
    print("=" * 50)
    print(type(e).__name__)
    print(str(e))
    