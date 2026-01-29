"use client";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { X } from "lucide-react";
import { Label } from "../ui/label";
import { useEditManager } from "@/atoms/edits";
import { useTimeContext } from "@/atoms/app-derived";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { EditMetadataControls } from "./edit-metadata-controls";
import { useEditableFieldState } from "./use-editable-field-state";
import { EditButton } from "./edit-button";
import { MetadataTooltip } from "./metadata-tooltip";
import { UnitImage } from "@/components/unit-image";
import { ImageUpload } from "@/components/image-upload";
import { Pencil } from "lucide-react";

// Validate file MIME type before creating blob URL for preview (CodeQL js/xss-through-dom)
const isValidImageFile = (file: File): boolean =>
  file.type.startsWith('image/');

interface EditableImageFieldWithMetadataProps {
  fieldId: string;
  label: string;
  imageId: number | null | undefined;
  unitType: "establishment" | "legal_unit" | "enterprise";
  formAction: (formData: FormData) => void;
  response: UpdateResponse;
  metadata?: Metadata;
}

export const EditableImageFieldWithMetadata = ({
  fieldId,
  label,
  imageId,
  unitType,
  formAction,
  response,
  metadata,
}: EditableImageFieldWithMetadataProps) => {
  const { selectedTimeContext } = useTimeContext();
  const [showResponse, setShowResponse] = useState(false);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [deleteImage, setDeleteImage] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const { currentEdit, setEditTarget, exitEditMode } = useEditManager();
  const isEditing = currentEdit?.fieldId === fieldId;

  const {
    hasUnsavedChanges,
    handleCancel: baseHandleCancel,
  } = useEditableFieldState(imageId ?? null, response, isEditing, exitEditMode);

  const handleCancel = () => {
    baseHandleCancel();
    setShowResponse(false);
    setSelectedFile(null);
    setDeleteImage(false);
  };

  const handleFileSelect = (file: File) => {
    setSelectedFile(file);
    setDeleteImage(false); // If selecting a file, cancel delete
    // Note: We'll set the file on the input in triggerFormSubmit to avoid React re-render issues
  };

  const handleDelete = () => {
    setDeleteImage(true);
    setSelectedFile(null); // If deleting, cancel file selection
  };

  const triggerFormSubmit = () => {
    // Set the file on the input right before submit to avoid React re-render issues
    if (selectedFile && fileInputRef.current) {
      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(selectedFile);
      fileInputRef.current.files = dataTransfer.files;
    }
    formRef.current?.requestSubmit();
    setShowResponse(true);
  };

  // Check if there are changes
  const hasImageChanges = selectedFile !== null || deleteImage;

  return (
    <form
      ref={formRef}
      action={formAction}
      className={`flex flex-col space-y-2 p-2 ${isEditing && "bg-ssb-light rounded-md"}`}
    >
      <div className="flex flex-col">
        <div className="flex items-center justify-between">
          <Label className="flex justify-between items-center h-10">
            <span className="text-xs uppercase text-gray-600">{label}</span>
            {metadata && <MetadataTooltip metadata={metadata} />}
          </Label>
          {!isEditing && (
            <EditButton
              className="h-8"
              variant="ghost"
              onClick={() =>
                setEditTarget(fieldId, {
                  validFrom: selectedTimeContext?.valid_from ?? null,
                  validTo: selectedTimeContext?.valid_to ?? null,
                })
              }
            >
              <Pencil className="text-zinc-700" />
            </EditButton>
          )}
        </div>

        <div className="flex items-center gap-4">
          {/* Show current or preview image */}
          {!deleteImage && (selectedFile && isValidImageFile(selectedFile) ? (
            <div className="h-24 w-24 rounded-lg overflow-hidden border-2 border-gray-300">
              <img
                src={URL.createObjectURL(selectedFile)}
                alt="Preview"
                className="h-full w-full object-cover"
              />
            </div>
          ) : imageId ? (
            <UnitImage
              imageId={imageId}
              unitType={unitType}
              className="h-24 w-24"
            />
          ) : null)}

          {isEditing && (
            <div className="flex items-center gap-2">
              {/* Delete button - only show if there's an existing image and no file selected */}
              {imageId && !selectedFile && !deleteImage && (
                <Button
                  type="button"
                  variant="destructive"
                  size="icon"
                  onClick={handleDelete}
                  title="Delete image"
                >
                  <X className="h-4 w-4" />
                </Button>
              )}
              
              {/* Undo delete button */}
              {deleteImage && (
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setDeleteImage(false)}
                >
                  Undo delete
                </Button>
              )}

              {/* File upload */}
              {!deleteImage && (
                <ImageUpload
                  onFileSelect={handleFileSelect}
                  maxSizeMB={4}
                />
              )}
            </div>
          )}
        </div>

        {isEditing && (
          <>
            <EditMetadataControls fieldId={fieldId} />
            <input type="hidden" name="delete_image" value={deleteImage ? "true" : "false"} />
            {/* Hidden file input - populated right before submit */}
            <input 
              ref={fileInputRef}
              type="file" 
              name="image" 
              accept="image/*" 
              className="hidden"
            />
            {showResponse && response && (
              <SubmissionFeedbackDebugInfo state={response} />
            )}
            <div className="flex gap-2 mt-2">
              <Button type="button" onClick={handleCancel} variant="outline">
                Cancel
              </Button>
              <Button
                type="button"
                onClick={triggerFormSubmit}
                disabled={!hasImageChanges}
              >
                {deleteImage ? "Delete" : selectedFile ? "Upload" : "Save"}
              </Button>
            </div>
          </>
        )}
      </div>
    </form>
  );
};
