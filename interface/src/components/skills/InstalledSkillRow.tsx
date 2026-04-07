import {cx} from "class-variance-authority";
import {Badge} from "@spacedrive/primitives";
import type {SkillInfo} from "@/api/client";

interface InstalledSkillRowProps {
	skill: SkillInfo;
	isSelected: boolean;
	onClick: () => void;
}

export function InstalledSkillRow({
	skill,
	isSelected,
	onClick,
}: InstalledSkillRowProps) {
	return (
		<button
			onClick={onClick}
			className={cx(
				"flex w-full flex-col gap-0.5 rounded-md px-2.5 py-2 text-left transition-colors",
				isSelected
					? "bg-app-dark-box text-ink"
					: "text-ink-dull hover:bg-app-dark-box/50 hover:text-ink",
			)}
		>
			<div className="flex items-center gap-1.5 min-w-0">
				<span className="truncate text-sm font-medium">{skill.name}</span>
				<Badge
					// variant={skill.source === "instance" ? "default" : "success"}
					size="sm"
					// className="shrink-0"
				>
					{skill.source}
				</Badge>
			</div>
			{skill.description && (
				<span className="truncate text-xs text-ink-faint">
					{skill.description}
				</span>
			)}
		</button>
	);
}
