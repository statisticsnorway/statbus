import React, { useState } from 'react'
import PropTypes from 'prop-types'
import { Button, Icon, Modal, Checkbox, TextArea, Grid } from 'semantic-ui-react'

import ConnectedForm from './ConnectedForm.js'
import styles from './styles.scss'

const { func, number, shape, string } = PropTypes

const Mandatory = '1'
const NotMandatory = '2'

function EditStatUnitPage({ type, regId, submitStatUnit, localize, goBack, errors }) {
  const [changeReason, setChangeReason] = useState(Mandatory)
  const [editComment, setEditComment] = useState('')
  const [statUnitToSubmit, setStatUnitToSubmit] = useState(undefined)
  const [formikBag, setFormikBag] = useState(undefined)

  const isMandatory = changeReason === Mandatory

  const handleSubmit = () => {
    if (statUnitToSubmit) {
      submitStatUnit(
        type,
        {
          ...statUnitToSubmit,
          regId,
          changeReason,
          editComment,
        },
        formikBag,
      )
      setStatUnitToSubmit(undefined)
      setFormikBag(undefined)
    }
  }

  const handleModalEdit = (_, { name, value }) => {
    if (name === 'changeReason') {
      setChangeReason(value)
    } else if (name === 'editComment') {
      setEditComment(value)
    }
  }

  const showModal = (statUnit, formik) => {
    setStatUnitToSubmit(statUnit)
    setFormikBag(formik)
  }

  const hideModal = () => {
    if (formikBag) {
      formikBag.setSubmitting(false)
    }
    setStatUnitToSubmit(undefined)
    setFormikBag(undefined)
  }

  const header = isMandatory ? 'CommentIsMandatory' : 'CommentIsNotMandatory'

  return (
    <div className={styles.root}>
      <ConnectedForm
        onSubmit={showModal}
        localize={localize}
        errors={errors}
        type={type}
        regId={regId}
        showSummary
        goBack={goBack}
      />
      <Modal open={statUnitToSubmit !== undefined}>
        <Modal.Header content={localize(header)} />
        <Modal.Content>
          <Grid>
            <Grid.Row>
              <Grid.Column width="3">
                <Checkbox
                  name="changeReason"
                  value={Mandatory}
                  checked={isMandatory}
                  onChange={handleModalEdit}
                  label={localize('Editing')}
                  radio
                />
                <Checkbox
                  name="changeReason"
                  value={NotMandatory}
                  checked={!isMandatory}
                  onChange={handleModalEdit}
                  label={localize('Correcting')}
                  radio
                />
                <br key="modal_reason_radio_br" />
                <Icon name={isMandatory ? 'edit' : 'write'} size="massive" />
              </Grid.Column>
              <Grid.Column width="13" className="ui form">
                <TextArea
                  name="editComment"
                  value={editComment}
                  onChange={handleModalEdit}
                  rows={8}
                />
              </Grid.Column>
            </Grid.Row>
          </Grid>
        </Modal.Content>
        <Modal.Actions>
          <Button.Group>
            <Button onClick={hideModal} content={localize('ButtonCancel')} negative />
            <Button
              onClick={handleSubmit}
              disabled={isMandatory && editComment === ''}
              content={localize('Submit')}
              positive
            />
          </Button.Group>
        </Modal.Actions>
      </Modal>
    </div>
  )
}

EditStatUnitPage.propTypes = {
  type: number.isRequired,
  regId: number.isRequired,
  submitStatUnit: func.isRequired,
  localize: func.isRequired,
  goBack: func.isRequired,
  errors: shape({
    message: string,
  }),
}

EditStatUnitPage.defaultProps = {
  errors: undefined,
}

export default EditStatUnitPage
