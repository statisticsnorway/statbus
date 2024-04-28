import React, { useState, useEffect } from 'react'
import { func, arrayOf, shape, string, number, oneOfType, bool } from 'prop-types'
import { Item, Confirm, Modal, Button } from 'semantic-ui-react'
import { isEmpty } from 'ramda'

import { getSearchFormErrors, getCorrectQuery } from '/helpers/validation'
import Paginate from '/components/Paginate'
import SearchForm from '../SearchForm.jsx'
import ListItem from './ListItem.jsx'
import styles from './styles.scss'

function DeletedList({
  actions: {
    updateFilter,
    setQuery,
    fetchData,
    restore,
    clearSearchFormForDeleted,
    setSearchConditionForDeleted,
  },
  formData,
  statUnits,
  query,
  totalCount,
  localize,
  locale,
  isLoading,
}) {
  const [displayConfirm, setDisplayConfirm] = useState(false)
  const [selectedUnit, setSelectedUnit] = useState(undefined)
  const [restoreFailed, setRestoreFailed] = useState(undefined)

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const handleChangeForm = (name, value) => {
    updateFilter({ [name]: value })
  }

  const handleSubmitForm = (e) => {
    e.preventDefault()
    if (!isEmpty(formData)) {
      const qdata = getCorrectQuery({ ...query, ...formData })
      qdata.page = 1
      setQuery(qdata)
    }
  }

  const showConfirm = (unit) => {
    setSelectedUnit(unit)
    setDisplayConfirm(true)
  }

  const setError = (message) => {
    setRestoreFailed(message)
  }

  const clearError = () => {
    setRestoreFailed(undefined)
  }

  const handleConfirm = () => {
    const queryParams = { ...query, ...formData }
    setSelectedUnit(undefined)
    setDisplayConfirm(false)
    const unitIndex = statUnits.indexOf(selectedUnit)
    restore(selectedUnit.type, selectedUnit.regId, queryParams, unitIndex, setError)
  }

  const handleCancel = () => {
    setSelectedUnit(undefined)
    setDisplayConfirm(false)
  }

  const handleResetForm = () => {
    clearSearchFormForDeleted()
    setQuery({})
  }

  const renderConfirm = () => (
    <Confirm
      open={displayConfirm}
      header={`${localize('AreYouSure')}`}
      content={`${localize('UndeleteStatUnitMessage')} "${selectedUnit.name}"?`}
      onConfirm={handleConfirm}
      onCancel={handleCancel}
    />
  )

  const renderErrorModal = () => (
    <Modal
      className="errorModal"
      size="small"
      open={restoreFailed !== undefined}
      onClose={clearError}
    >
      <Modal.Header>{localize('Error')}</Modal.Header>
      <Modal.Content>{localize(restoreFailed)}</Modal.Content>
      <Modal.Actions>
        <Button primary onClick={clearError} content={localize('Ok')} />
      </Modal.Actions>
    </Modal>
  )

  const renderRow = item => (
    <ListItem
      key={`${item.regId}_${item.type}`}
      statUnit={item}
      restore={showConfirm}
      localize={localize}
    />
  )

  return (
    <div className={styles.root}>
      {displayConfirm && renderConfirm()}
      {renderErrorModal()}
      <h2>{localize('SearchDeletedStatisticalUnits')}</h2>
      <SearchForm
        formData={formData}
        onChange={handleChangeForm}
        onSubmit={handleSubmitForm}
        onReset={handleResetForm}
        setSearchCondition={setSearchConditionForDeleted}
        locale={locale}
        errors={getSearchFormErrors(formData, localize)}
        localize={localize}
        disabled={isLoading}
      />
      <Paginate totalCount={Number(totalCount)} updateFilter={updateFilter}>
        <Item.Group divided className={styles.items}>
          {statUnits.map(renderRow)}
        </Item.Group>
      </Paginate>
    </div>
  )
}

DeletedList.propTypes = {
  actions: shape({
    updateFilter: func.isRequired,
    setQuery: func.isRequired,
    fetchData: func.isRequired,
    restore: func.isRequired,
    clearSearchFormForDeleted: func.isRequired,
    setSearchConditionForDeleted: func.isRequired,
  }).isRequired,
  formData: shape({}).isRequired,
  statUnits: arrayOf(shape({
    regId: number.isRequired,
    name: string.isRequired,
  })),
  query: shape({
    wildcard: string,
    includeLiquidated: string,
  }),
  totalCount: oneOfType([number, string]),
  localize: func.isRequired,
  locale: string.isRequired,
  isLoading: bool.isRequired,
}

DeletedList.defaultProps = {
  query: {
    wildcard: '',
    includeLiquidated: false,
  },
  statUnits: [],
  totalCount: 0,
}

export default DeletedList
