"use client";
import { useTimeContext } from "@/app/time-context";
import NextLink, { LinkProps as NextLinkProps } from "next/link";
import { FC } from "react";

interface TimeContextLinkProps extends NextLinkProps {
  children: React.ReactNode;
  className?: string;
}

const TimeContextLink: FC<TimeContextLinkProps> = ({ href, children, className, ...props }) => {
  const { appendTcParam } = useTimeContext();

  const modifiedHref =
    typeof href === "string"
      ? appendTcParam(href)
      : href;

  return (
    <NextLink href={modifiedHref} className={className} {...props}>
      {children}
    </NextLink>
  );
};

export { TimeContextLink };
