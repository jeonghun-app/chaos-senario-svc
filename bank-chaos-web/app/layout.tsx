import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Bank Chaos Web - Monitoring Dashboard",
  description: "AWS Chaos Engineering Demo - Monitoring Dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head />
      <body>
        {children}
      </body>
    </html>
  );
}
