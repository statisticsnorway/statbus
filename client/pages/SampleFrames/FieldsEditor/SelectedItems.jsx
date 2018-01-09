import React from 'react'
import PropTypes from 'prop-types'
import { DragDropContext, Draggable, Droppable } from 'react-beautiful-dnd'
import { List, Label } from 'semantic-ui-react'

import { predicateFields } from 'helpers/enums'

const styleItem = (draggableStyle, isDragging) => ({
  userSelect: 'none',
  padding: '2px',
  background: isDragging ? 'lightgreen' : 'white',
  ...draggableStyle,
})
const styleList = isDraggingOver => ({
  background: isDraggingOver ? 'lightblue' : 'white',
})

const SelectedItems = ({ value, onChange, onRemove, localize }) => {
  const onDragEnd = ({ source, destination }) => {
    if (destination == null) return
    const result = Array.from(value)
    const [removed] = result.splice(source.index, 1)
    result.splice(destination.index, 0, removed)
    onChange(result)
  }
  return (
    <DragDropContext onDragEnd={onDragEnd}>
      <Droppable droppableId="selectedItemsDroppable">
        {(droppable, { isDraggingOver }) => (
          <List>
            <div ref={droppable.innerRef} style={styleList(isDraggingOver)}>
              {value.map(key => (
                <Draggable key={key} draggableId={`selectedItemDraggable${key}`}>
                  {(draggable, { isDragging }) => (
                    <List.Item>
                      <div
                        ref={draggable.innerRef}
                        style={styleItem(draggable.draggableStyle, isDragging)}
                        {...draggable.dragHandleProps}
                      >
                        <Label
                          id={key}
                          content={localize(predicateFields.get(key))}
                          onRemove={onRemove}
                          size="large"
                        />
                      </div>
                      {draggable.placeholder}
                    </List.Item>
                  )}
                </Draggable>
              ))}
              {droppable.placeholder}
            </div>
          </List>
        )}
      </Droppable>
    </DragDropContext>
  )
}

const { arrayOf, func, number } = PropTypes
SelectedItems.propTypes = {
  value: arrayOf(number).isRequired,
  onChange: func.isRequired,
  onRemove: func.isRequired,
  localize: func.isRequired,
}

export default SelectedItems
