import React from 'react'
import PropTypes from 'prop-types'
import { DragDropContext, Draggable, Droppable } from 'react-beautiful-dnd'
import { List } from 'semantic-ui-react'
import * as R from 'ramda'

const ListWithDnd = ({ value, renderItem, getItemKey, id, listProps, listItemProps, onChange }) => {
  const onDragEnd = ({ source, destination }) => {
    if (destination == null) return
    const result = Array.from(value)
    const [removed] = result.splice(source.index, 1)
    result.splice(destination.index, 0, removed)
    onChange(result)
  }
  return (
    <DragDropContext onDragEnd={onDragEnd}>
      <Droppable droppableId={`droppable-${id}`}>
        {(droppable, { isDraggingOver }) => (
          <List {...listProps}>
            <div
              ref={droppable.innerRef}
              style={{ background: isDraggingOver ? 'lightblue' : 'white' }}
            >
              {value.map((item, i) => (
                <Draggable
                  key={getItemKey(item)}
                  draggableId={`draggable-${id}-${getItemKey(item)}`}
                  index={i}
                >
                  {({ innerRef, draggableProps, dragHandleProps, placeholder }, { isDragging }) => (
                    <List.Item
                      {...(typeof listItemProps === 'function'
                        ? listItemProps(item, i)
                        : listItemProps)}
                    >
                      <div
                        {...{
                          ref: innerRef,
                          ...draggableProps,
                          ...dragHandleProps,
                          style: {
                            ...draggableProps.style,
                            userSelect: 'none',
                            padding: '2px',
                            background: isDragging ? 'lightgreen' : 'white',
                          },
                        }}
                      >
                        {renderItem(item, i)}
                      </div>
                      {placeholder}
                    </List.Item>
                  )}
                </Draggable>
              ))}
            </div>
          </List>
        )}
      </Droppable>
    </DragDropContext>
  )
}

const { array, arrayOf, func, oneOfType, number, shape, string } = PropTypes
ListWithDnd.propTypes = {
  value: arrayOf(oneOfType([shape({}), string, number, array])).isRequired,
  renderItem: func.isRequired,
  getItemKey: func,
  id: string,
  listProps: shape({}),
  listItemProps: oneOfType([func, shape({})]),
  onChange: func.isRequired,
}
ListWithDnd.defaultProps = {
  getItemKey: R.identity,
  id: 'ListWithDnd',
  listProps: {},
  listItemProps: {},
}

export default ListWithDnd
